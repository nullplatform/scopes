#!/usr/bin/env bats
# =============================================================================
# Unit tests for log/log script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats azure-apps/log/tests/scripts/log_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  AZURE_APPS_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$AZURE_APPS_DIR/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  SCRIPT_PATH="$PROJECT_DIR/log"
  MOCKS_DIR="$AZURE_APPS_DIR/deployment/tests/resources/mocks"
  RESPONSES_DIR="$MOCKS_DIR/responses"

  # Add mocks to PATH
  export PATH="$MOCKS_DIR:$PATH"

  # Set env vars (normally set by build_context)
  export APP_NAME="tools-automation-development-tools-7"
  export SCOPE_ID="7"
  export APPLICATION_ID="4"
  export DEPLOYMENT_ID="8"
  export FILTER_PATTERN=""
  export INSTANCE_ID=""
  export LIMIT=""
  export START_TIME=""
  export NEXT_PAGE_TOKEN=""

  # Set Azure env vars (normally from build_context via np provider list)
  export AZURE_RESOURCE_GROUP="test-resource-group"
  export ARM_CLIENT_ID="test-client-id"
  export ARM_CLIENT_SECRET="test-client-secret"
  export ARM_TENANT_ID="test-tenant-id"
  export ARM_SUBSCRIPTION_ID="test-subscription-id"

  # Configure az mock to return publishing credentials
  export AZ_MOCK_RESPONSE="$RESPONSES_DIR/az_publishing_credentials.json"
  export AZ_MOCK_EXIT_CODE=0
  export AZ_CALL_LOG=$(mktemp)

  # Configure curl mock
  export CURL_CALL_LOG=$(mktemp)
  export CURL_MOCK_EXIT_CODE=0

  # Create a combined curl mock that returns different responses based on URL
  export CURL_RESPONSE_DIR=$(mktemp -d)
  # Default: return the log list
  export CURL_MOCK_RESPONSE="$RESPONSES_DIR/kudu_docker_logs_list.json"
}

teardown() {
  rm -f "$AZ_CALL_LOG" "$CURL_CALL_LOG"
  rm -rf "${CURL_RESPONSE_DIR:-}"
}

# =============================================================================
# Test: Publishing credentials
# =============================================================================
@test "Should fetch publishing credentials via az CLI" {
  run source "$SCRIPT_PATH"

  local calls
  calls=$(cat "$AZ_CALL_LOG")
  assert_contains "$calls" "webapp deployment list-publishing-credentials"
  assert_contains "$calls" "--resource-group test-resource-group"
  assert_contains "$calls" "--name tools-automation-development-tools-7"
}

# =============================================================================
# Test: Kudu API calls
# =============================================================================
@test "Should call Kudu API with correct URL" {
  run source "$SCRIPT_PATH"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "tools-automation-development-tools-7.scm.azurewebsites.net/api/logs/docker"
}

@test "Should call Kudu API with credentials" {
  run source "$SCRIPT_PATH"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "-u"
}

# =============================================================================
# Test: Output format
# =============================================================================
@test "Should produce valid JSON output with results array" {
  # Use a simpler mock: curl returns the log list, then log file content
  # For this test, we just verify the structure with the mock returning log list
  run source "$SCRIPT_PATH"

  # Output should be valid JSON
  local json_valid
  json_valid=$(echo "$output" | jq '.' >/dev/null 2>&1 && echo "true" || echo "false")
  assert_equal "$json_valid" "true"
}

@test "Should include results key in output" {
  run source "$SCRIPT_PATH"

  local has_results
  has_results=$(echo "$output" | jq 'has("results")' 2>/dev/null || echo "false")
  assert_equal "$has_results" "true"
}

@test "Should include next_page_token key in output" {
  run source "$SCRIPT_PATH"

  local has_token
  has_token=$(echo "$output" | jq 'has("next_page_token")' 2>/dev/null || echo "false")
  assert_equal "$has_token" "true"
}

# =============================================================================
# Test: Empty results
# =============================================================================
@test "Should return empty results when no logs available" {
  export CURL_MOCK_RESPONSE="$CURL_RESPONSE_DIR/empty_logs.json"
  echo "[]" > "$CURL_MOCK_RESPONSE"

  run source "$SCRIPT_PATH"

  local count
  count=$(echo "$output" | jq '.results | length' 2>/dev/null || echo "-1")
  assert_equal "$count" "0"
}
