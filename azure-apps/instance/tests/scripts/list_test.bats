#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/list script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats azure-apps/instance/tests/scripts/list_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  AZURE_APPS_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$AZURE_APPS_DIR/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  SCRIPT_PATH="$PROJECT_DIR/list"
  MOCKS_DIR="$AZURE_APPS_DIR/deployment/tests/resources/mocks"
  RESPONSES_DIR="$MOCKS_DIR/responses"

  # Add mocks to PATH
  export PATH="$MOCKS_DIR:$PATH"

  # Set env vars (normally set by build_context)
  export APP_NAME="tools-automation-development-tools-7"
  export SCOPE_ID="7"
  export APPLICATION_ID="4"
  export DEPLOYMENT_ID="8"
  export LIMIT="10"

  # Set Azure env vars (normally from build_context via np provider list)
  export AZURE_RESOURCE_GROUP="test-resource-group"
  export ARM_SUBSCRIPTION_ID="test-subscription-id"
  export AZURE_ACCESS_TOKEN="mock-azure-token"

  # Configure curl mock
  export CURL_CALL_LOG=$(mktemp)
  export CURL_MOCK_EXIT_CODE=0
}

teardown() {
  rm -f "$CURL_CALL_LOG"
}

# =============================================================================
# Test: Azure REST API call
# =============================================================================
@test "Should call Azure REST API for instances" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "/instances"
  assert_contains "$calls" "Authorization: Bearer"
}

# =============================================================================
# Test: Output structure
# =============================================================================
@test "Should produce valid JSON output with results array" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local has_results
  has_results=$(echo "$output" | jq 'has("results")')
  assert_equal "$has_results" "true"
}

@test "Should return correct number of instances" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local count
  count=$(echo "$output" | jq '.results | length')
  assert_equal "$count" "2"
}

@test "Should include instance id in results" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local first_id
  first_id=$(echo "$output" | jq -r '.results[0].id')
  assert_equal "$first_id" "instance1"
}

@test "Should include selector with scope_id" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local scope_id
  scope_id=$(echo "$output" | jq -r '.results[0].selector.scope_id')
  assert_equal "$scope_id" "7"
}

@test "Should include dns in details" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local dns
  dns=$(echo "$output" | jq -r '.results[0].details.dns')
  assert_equal "$dns" "tools-automation-development-tools-7.azurewebsites.net"
}

@test "Should include state in results" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local state
  state=$(echo "$output" | jq -r '.results[0].state')
  assert_equal "$state" "Running"
}

# =============================================================================
# Test: Empty instances
# =============================================================================
@test "Should return empty results when no instances running" {
  # Override curl mock for empty response
  export CURL_MOCK_RESPONSE=$(mktemp)
  echo '{"value":[]}' > "$CURL_MOCK_RESPONSE"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local count
  count=$(echo "$output" | jq '.results | length')
  assert_equal "$count" "0"

  rm -f "$CURL_MOCK_RESPONSE"
}
