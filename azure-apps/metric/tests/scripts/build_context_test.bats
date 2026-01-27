#!/usr/bin/env bats
# =============================================================================
# Unit tests for metric/build_context script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats azure-apps/metric/tests/scripts/build_context_test.bats
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

  # Load test context (CONTEXT = .notification)
  export CONTEXT=$(cat "$PROJECT_DIR/tests/resources/metric_context.json")

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
# Test: Context extraction - arguments as env vars
# =============================================================================
@test "Should export SCOPE_ID from context arguments" {
  run_build_context

  assert_equal "$SCOPE_ID" "7"
}

@test "Should export START_TIME from context arguments" {
  run_build_context

  assert_equal "$START_TIME" "2026-01-27T00:00:00Z"
}

@test "Should export END_TIME from context arguments" {
  run_build_context

  assert_equal "$END_TIME" "2026-01-27T01:00:00Z"
}

@test "Should export INTERVAL from context arguments" {
  run_build_context

  assert_equal "$INTERVAL" "5"
}

# =============================================================================
# Test: METRIC to METRIC_NAME mapping
# =============================================================================
@test "Should map METRIC to METRIC_NAME" {
  run_build_context

  assert_equal "$METRIC_NAME" "system.cpu_usage_percentage"
}

# =============================================================================
# Test: APP_NAME resolution
# =============================================================================
@test "Should resolve APP_NAME via np CLI and generate_resource_name" {
  run_build_context

  assert_equal "$APP_NAME" "tools-automation-development-tools-7"
}

# =============================================================================
# Test: AZURE_RESOURCE_ID
# =============================================================================
@test "Should build AZURE_RESOURCE_ID from resolved credentials and APP_NAME" {
  run_build_context

  local expected="/subscriptions/test-subscription-id/resourceGroups/test-resource-group/providers/Microsoft.Web/sites/tools-automation-development-tools-7"
  assert_equal "$AZURE_RESOURCE_ID" "$expected"
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
@test "Should fail when scope_id is missing from context" {
  export CONTEXT='{"arguments":{}}'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Missing required parameter: scope_id"
}
