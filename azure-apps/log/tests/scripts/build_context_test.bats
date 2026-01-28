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

  # Set np mock responses (only provider list is called now)
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

# =============================================================================
# Test: Slug extraction from context (no np calls)
# =============================================================================
@test "Should extract scope slug from context" {
  run_build_context

  # APP_NAME is built from slugs, verify it's correct
  assert_equal "$APP_NAME" "tools-automation-development-tools-7"
}

# =============================================================================
# Test: np CLI calls (only provider list now)
# =============================================================================
@test "Should call np provider list with cloud-providers category" {
  run_build_context

  local calls
  calls=$(cat "$NP_CALL_LOG")
  assert_contains "$calls" "provider list --categories cloud-providers"
}

@test "Should not call np scope read" {
  run_build_context

  local calls
  calls=$(cat "$NP_CALL_LOG")
  # Should NOT contain scope read
  if [[ "$calls" == *"scope read"* ]]; then
    echo "Expected no 'scope read' call, but found one"
    return 1
  fi
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
  export NP_ACTION_CONTEXT='{"notification":{"arguments":{},"scope":{"slug":"test"},"tags":{"namespace":"ns","application":"app"}}}'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Missing required parameter: SCOPE_ID"
}

@test "Should fail when slugs are missing from context" {
  export NP_ACTION_CONTEXT='{"notification":{"arguments":{"scope_id":"7"},"scope":{},"tags":{}}}'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Could not extract slugs from context"
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
