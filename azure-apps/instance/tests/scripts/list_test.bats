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

  # Configure az mock
  export AZ_MOCK_RESPONSE="$RESPONSES_DIR/az_list_instances.json"
  export AZ_MOCK_EXIT_CODE=0
  export AZ_CALL_LOG=$(mktemp)
}

teardown() {
  rm -f "$AZ_CALL_LOG"
}

# =============================================================================
# Test: Azure CLI call
# =============================================================================
@test "Should call az webapp list-instances with correct parameters" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$AZ_CALL_LOG")
  assert_contains "$calls" "webapp list-instances"
  assert_contains "$calls" "--resource-group test-resource-group"
  assert_contains "$calls" "--name tools-automation-development-tools-7"
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
  assert_equal "$first_id" "instance-001"
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
  local empty_file
  empty_file=$(mktemp)
  echo "[]" > "$empty_file"
  export AZ_MOCK_RESPONSE="$empty_file"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local count
  count=$(echo "$output" | jq '.results | length')
  assert_equal "$count" "0"

  rm -f "$empty_file"
}
