#!/usr/bin/env bats
# =============================================================================
# Unit tests for distribution/cloudfront/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/distribution/cloudfront/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/distribution/cloudfront/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"
  MOCKS_DIR="$RESOURCES_DIR/np_mocks"

  # Load shared test utilities
  source "$PROJECT_DIR/tests/test_utils.bash"

  # Add mock np to PATH (must be first)
  export PATH="$MOCKS_DIR:$PATH"

  # Load context
  export CONTEXT=$(cat "$RESOURCES_DIR/context.json")

  # Initialize TOFU_VARIABLES with required fields
  export TOFU_VARIABLES='{
    "application_slug": "automation",
    "scope_slug": "development-tools",
    "scope_id": "7"
  }'

  export MODULES_TO_USE=""
}

# =============================================================================
# Helper functions
# =============================================================================
run_cloudfront_setup() {
  source "$SCRIPT_PATH"
}

set_np_mock() {
  local mock_file="$1"
  local exit_code="${2:-0}"
  export NP_MOCK_RESPONSE="$MOCKS_DIR/asset_repository/$mock_file"
  export NP_MOCK_EXIT_CODE="$exit_code"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "TOFU_VARIABLES matches expected structure on success" {
  set_np_mock "success.json"

  run_cloudfront_setup

  # Expected JSON - update this when adding new fields
  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "hosting_bucket_name": "assets-kwik-e-mart-main",
  "hosting_app_name": "automation-development-tools-7",
  "hosting_s3_prefix": "/app"
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "adds module to MODULES_TO_USE when empty" {
  set_np_mock "success.json"

  run_cloudfront_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/distribution/cloudfront/modules"
}

@test "appends module to existing MODULES_TO_USE" {
  set_np_mock "success.json"
  export MODULES_TO_USE="existing/module"

  run_cloudfront_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/distribution/cloudfront/modules"
}

# =============================================================================
# Test: Auth error case
# =============================================================================
@test "fails with auth error" {
  set_np_mock "auth_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Failed to fetch assets-repository provider"
}

@test "shows permission denied message for 403 error" {
  set_np_mock "auth_error.json" 1

  run source "$SCRIPT_PATH"

  assert_contains "$output" "Permission denied"
}

# =============================================================================
# Test: No providers found case
# =============================================================================
@test "fails when no bucket data in providers" {
  set_np_mock "no_bucket_data.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "No S3 bucket found in assets-repository providers"
}

@test "shows provider count when no bucket found" {
  set_np_mock "no_bucket_data.json"

  run source "$SCRIPT_PATH"

  assert_contains "$output" "Found 1 provider(s)"
}

# =============================================================================
# Test: Empty results case
# =============================================================================
@test "fails when no providers returned" {
  set_np_mock "no_data.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "No S3 bucket found in assets-repository providers"
}

@test "shows zero providers found" {
  set_np_mock "no_data.json"

  run source "$SCRIPT_PATH"

  assert_contains "$output" "Found 0 provider(s)"
}

