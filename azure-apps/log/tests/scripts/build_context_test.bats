#!/usr/bin/env bats
# =============================================================================
# Unit tests for log/build_context script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats azure-apps/log/tests/scripts/build_context_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  AZURE_APPS_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$AZURE_APPS_DIR/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  SCRIPT_PATH="$PROJECT_DIR/build_context"
  MOCKS_DIR="$AZURE_APPS_DIR/deployment/tests/resources/mocks"
  RESPONSES_DIR="$MOCKS_DIR/responses"

  # Add mocks to PATH
  export PATH="$MOCKS_DIR:$PATH"

  # Load test context
  export NP_ACTION_CONTEXT=$(cat "$PROJECT_DIR/tests/resources/log_action_context.json")

  # Set SERVICE_PATH (azure-apps root)
  export SERVICE_PATH="$AZURE_APPS_DIR"

  # Set np mock responses
  export NP_SCOPE_RESPONSE="$RESPONSES_DIR/np_scope_read.json"
  export NP_APP_RESPONSE="$RESPONSES_DIR/np_application_read.json"
  export NP_NAMESPACE_RESPONSE="$RESPONSES_DIR/np_namespace_read.json"
  export NP_PROVIDER_RESPONSE="$RESPONSES_DIR/np_provider_list.json"

  # ARM_CLIENT_SECRET is an env var set on the agent (not from provider)
  export ARM_CLIENT_SECRET="test-client-secret"

  # Call logs
  export AZ_CALL_LOG=$(mktemp)
  export NP_CALL_LOG=$(mktemp)
  export AZ_MOCK_EXIT_CODE=0
  export NP_MOCK_EXIT_CODE=0
}

teardown() {
  rm -f "$AZ_CALL_LOG" "$NP_CALL_LOG"
}

run_build_context() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Context extraction
# =============================================================================
@test "Should extract SCOPE_ID from NP_ACTION_CONTEXT" {
  run_build_context

  assert_equal "$SCOPE_ID" "7"
}

@test "Should extract APPLICATION_ID from NP_ACTION_CONTEXT" {
  run_build_context

  assert_equal "$APPLICATION_ID" "4"
}

@test "Should extract DEPLOYMENT_ID from NP_ACTION_CONTEXT" {
  run_build_context

  assert_equal "$DEPLOYMENT_ID" "8"
}

@test "Should extract FILTER_PATTERN from NP_ACTION_CONTEXT" {
  run_build_context

  assert_equal "$FILTER_PATTERN" "ERROR"
}

@test "Should extract LIMIT from NP_ACTION_CONTEXT" {
  run_build_context

  assert_equal "$LIMIT" "100"
}

@test "Should extract START_TIME from NP_ACTION_CONTEXT" {
  run_build_context

  assert_equal "$START_TIME" "2026-01-27T00:00:00Z"
}

@test "Should default optional fields to empty when not provided" {
  export NP_ACTION_CONTEXT='{"notification":{"arguments":{"scope_id":"7"}}}'

  run_build_context

  assert_empty "$FILTER_PATTERN" "FILTER_PATTERN"
  assert_empty "$INSTANCE_ID" "INSTANCE_ID"
  assert_empty "$LIMIT" "LIMIT"
  assert_empty "$START_TIME" "START_TIME"
  assert_empty "$NEXT_PAGE_TOKEN" "NEXT_PAGE_TOKEN"
}

# =============================================================================
# Test: np CLI calls
# =============================================================================
@test "Should call np scope read with correct SCOPE_ID" {
  run_build_context

  local calls
  calls=$(cat "$NP_CALL_LOG")
  assert_contains "$calls" "scope read --id 7 --format json"
}

@test "Should call np application read with correct APPLICATION_ID" {
  run_build_context

  local calls
  calls=$(cat "$NP_CALL_LOG")
  assert_contains "$calls" "application read --id 4 --format json"
}

@test "Should call np namespace read with correct NAMESPACE_ID" {
  run_build_context

  local calls
  calls=$(cat "$NP_CALL_LOG")
  assert_contains "$calls" "namespace read --id 3 --format json"
}

@test "Should call np provider list with cloud-providers category" {
  run_build_context

  local calls
  calls=$(cat "$NP_CALL_LOG")
  assert_contains "$calls" "provider list --categories cloud-providers"
}

# =============================================================================
# Test: APP_NAME resolution
# =============================================================================
@test "Should resolve APP_NAME via np CLI and generate_resource_name" {
  run_build_context

  assert_equal "$APP_NAME" "tools-automation-development-tools-7"
}

# =============================================================================
# Test: Azure credentials from provider
# =============================================================================
@test "Should resolve ARM_SUBSCRIPTION_ID from cloud provider" {
  run_build_context

  assert_equal "$ARM_SUBSCRIPTION_ID" "test-subscription-id"
}

@test "Should resolve ARM_CLIENT_ID from cloud provider" {
  run_build_context

  assert_equal "$ARM_CLIENT_ID" "test-client-id"
}

@test "Should resolve ARM_TENANT_ID from cloud provider" {
  run_build_context

  assert_equal "$ARM_TENANT_ID" "test-tenant-id"
}

@test "Should resolve AZURE_RESOURCE_GROUP from cloud provider" {
  run_build_context

  assert_equal "$AZURE_RESOURCE_GROUP" "test-resource-group"
}

# =============================================================================
# Test: Azure login
# =============================================================================
@test "Should login to Azure with service principal credentials" {
  run_build_context

  local calls
  calls=$(cat "$AZ_CALL_LOG")
  assert_contains "$calls" "login --service-principal -u test-client-id -p test-client-secret --tenant test-tenant-id --output none"
}

@test "Should set the Azure subscription" {
  run_build_context

  local calls
  calls=$(cat "$AZ_CALL_LOG")
  assert_contains "$calls" "account set --subscription test-subscription-id --output none"
}

# =============================================================================
# Test: Validation
# =============================================================================
@test "Should fail when SCOPE_ID is missing from context" {
  export NP_ACTION_CONTEXT='{"notification":{"arguments":{}}}'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Missing required parameter: SCOPE_ID"
}

# =============================================================================
# Test: Exports
# =============================================================================
@test "Should export all required env vars" {
  run_build_context

  assert_not_empty "$SCOPE_ID" "SCOPE_ID"
  assert_not_empty "$APP_NAME" "APP_NAME"
  assert_not_empty "$ARM_SUBSCRIPTION_ID" "ARM_SUBSCRIPTION_ID"
  assert_not_empty "$ARM_CLIENT_ID" "ARM_CLIENT_ID"
  assert_not_empty "$ARM_TENANT_ID" "ARM_TENANT_ID"
  assert_not_empty "$AZURE_RESOURCE_GROUP" "AZURE_RESOURCE_GROUP"
}
