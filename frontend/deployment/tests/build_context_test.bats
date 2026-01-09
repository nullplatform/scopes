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
  PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"

  CONTEXT=$(cat "$TEST_DIR/resources/context.json")
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
  source "$PROJECT_DIR/build_context"
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  if [ "$actual" != "$expected" ]; then
    echo "Expected: '$expected'"
    echo "Actual:   '$actual'"
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Expected string to contain: '$needle'"
    echo "Actual: '$haystack'"
    return 1
  fi
}

assert_not_empty() {
  local value="$1"
  local name="${2:-value}"
  if [ -z "$value" ]; then
    echo "Expected $name to be non-empty, but it was empty"
    return 1
  fi
}

assert_empty() {
  local value="$1"
  local name="${2:-value}"
  if [ -n "$value" ]; then
    echo "Expected $name to be empty"
    echo "Actual: '$value'"
    return 1
  fi
}

assert_directory_exists() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "Expected directory to exist: '$dir'"
    return 1
  fi
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "TOFU_VARIABLES matches expected structure" {
  run_build_context

  # Expected JSON - update this when adding new fields
  local expected='{
  "application_slug": "automation",
  "application_version": "v1.0.0",
  "env_vars_json": {
    "CLUSTER_NAME": "development-cluster",
    "TEST": "testing-tools"
  },
  "repository_url": "https://github.com/playground-repos/tools-automation",
  "resource_tags_json": {
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
  },
  "scope_id": "7",
  "scope_slug": "development-tools"
}'

  # Sort keys for consistent comparison
  local actual_sorted=$(echo "$TOFU_VARIABLES" | jq -S .)
  local expected_sorted=$(echo "$expected" | jq -S .)

  if [ "$actual_sorted" != "$expected_sorted" ]; then
    echo "TOFU_VARIABLES does not match expected structure"
    echo ""
    echo "Expected:"
    echo "$expected_sorted"
    echo ""
    echo "Actual:"
    echo "$actual_sorted"
    echo ""
    echo "Diff:"
    diff <(echo "$expected_sorted") <(echo "$actual_sorted") || true
    return 1
  fi
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES
# =============================================================================
@test "generates correct tf_state_key format" {
  run_build_context

  # Should contain the expected backend-config key

  assert_contains "$TOFU_INIT_VARIABLES" "key=frontend/tools/automation/development-tools-$scope_id"
}

# =============================================================================
# Test: TOFU_MODULE_DIR
# =============================================================================
@test "creates TOFU_MODULE_DIR with scope_id" {
  run_build_context

  # Should end with the scope_id
  assert_contains "$TOFU_MODULE_DIR" "$SERVICE_PATH/output/$scope_id"
}

@test "TOFU_MODULE_DIR is created as directory" {
  run_build_context

  assert_directory_exists "$TOFU_MODULE_DIR"
}

# =============================================================================
# Test: MODULES_TO_USE initialization
# =============================================================================
@test "MODULES_TO_USE is empty by default" {
  unset CUSTOM_TOFU_MODULES
  run_build_context

  assert_empty "$MODULES_TO_USE" "MODULES_TO_USE"
}

@test "MODULES_TO_USE inherits from CUSTOM_TOFU_MODULES" {
  export CUSTOM_TOFU_MODULES="custom/module1,custom/module2"
  run_build_context

  assert_equal "$MODULES_TO_USE" "custom/module1,custom/module2"
}

# =============================================================================
# Test: exports are set
# =============================================================================
@test "exports TOFU_VARIABLES" {
  run_build_context

  assert_not_empty "$TOFU_VARIABLES" "TOFU_VARIABLES"
}

@test "exports TOFU_INIT_VARIABLES" {
  run_build_context

  assert_not_empty "$TOFU_INIT_VARIABLES" "TOFU_INIT_VARIABLES"
}

@test "exports TOFU_MODULE_DIR" {
  run_build_context

  assert_not_empty "$TOFU_MODULE_DIR" "TOFU_MODULE_DIR"
}
