#!/usr/bin/env bats
# =============================================================================
# Unit tests for build_context script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/build_context_test.bats
#
# Or run all tests:
#   bats tests/*.bats
# =============================================================================

scope_id=7

# Setup - runs before each test
setup() {
  # Get the directory of the test file
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  CONTEXT=$(cat "$PROJECT_DIR/tests/resources/context.json")
  SERVICE_PATH="$PROJECT_DIR"
  TEST_OUTPUT_DIR=$(mktemp -d)

  export CONTEXT SERVICE_PATH TEST_OUTPUT_DIR
}

# Teardown - runs after each test
teardown() {
  # Clean up temp directory
  if [ -d "$TEST_OUTPUT_DIR" ]; then
    rm -rf "$TEST_OUTPUT_DIR"
  fi
}

# =============================================================================
# Helper functions
# =============================================================================
run_build_context() {
  # Source the build_context script
  source "$PROJECT_DIR/scripts/build_context"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should generate TOFU_VARIABLES with expected structure" {
  run_build_context

  # Expected JSON - update this when adding new fields
  local expected='{}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES
# =============================================================================
@test "Should generate correct tf_state_key format in TOFU_INIT_VARIABLES" {
  run_build_context

  # Should contain the expected backend-config key

  assert_contains "$TOFU_INIT_VARIABLES" "key=frontend/tools/automation/development-tools-$scope_id"
}

# =============================================================================
# Test: TOFU_MODULE_DIR
# =============================================================================
@test "Should create TOFU_MODULE_DIR path with scope_id" {
  run_build_context

  # Should end with the scope_id
  assert_contains "$TOFU_MODULE_DIR" "$SERVICE_PATH/output/$scope_id"
}

@test "Should create TOFU_MODULE_DIR as a directory" {
  run_build_context

  assert_directory_exists "$TOFU_MODULE_DIR"
}

# =============================================================================
# Test: MODULES_TO_USE initialization
# =============================================================================
@test "Should initialize MODULES_TO_USE as empty by default" {
  unset CUSTOM_TOFU_MODULES
  run_build_context

  assert_empty "$MODULES_TO_USE" "MODULES_TO_USE"
}

@test "Should inherit MODULES_TO_USE from CUSTOM_TOFU_MODULES" {
  export CUSTOM_TOFU_MODULES="custom/module1,custom/module2"
  run_build_context

  assert_equal "$MODULES_TO_USE" "custom/module1,custom/module2"
}

# =============================================================================
# Test: exports are set
# =============================================================================
@test "Should export TOFU_VARIABLES" {
  run_build_context

  assert_not_empty "$TOFU_VARIABLES" "TOFU_VARIABLES"
}

@test "Should export TOFU_INIT_VARIABLES" {
  run_build_context

  assert_not_empty "$TOFU_INIT_VARIABLES" "TOFU_INIT_VARIABLES"
}

@test "Should export TOFU_MODULE_DIR" {
  run_build_context

  assert_not_empty "$TOFU_MODULE_DIR" "TOFU_MODULE_DIR"
}

# =============================================================================
# Test: RESOURCE_TAGS_JSON - verifies the entire JSON structure
# =============================================================================
@test "Should generate RESOURCE_TAGS_JSON with expected structure" {
  run_build_context

  # Expected JSON - update this when adding new fields
  local expected='{
    "account": "playground",
    "account_id": 2,
    "application": "automation",
    "application_id": 4,
    "deployment_id": 8,
    "namespace": "tools",
    "namespace_id": 3,
    "nullplatform": "true",
    "scope": "development-tools",
    "scope_id": 7
  }'

  assert_json_equal "$RESOURCE_TAGS_JSON" "$expected" "RESOURCE_TAGS_JSON"
}