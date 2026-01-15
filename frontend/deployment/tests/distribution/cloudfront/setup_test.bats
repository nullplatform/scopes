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
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/distribution/cloudfront/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"
  MOCKS_DIR="$RESOURCES_DIR/np_mocks"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

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

# TODO(federico.maleh) move this to the assertions.sh and document
set_np_mock() {
  local mock_file="$1"
  local exit_code="${2:-0}"
  export NP_MOCK_RESPONSE="$MOCKS_DIR/asset_repository/$mock_file"
  export NP_MOCK_EXIT_CODE="$exit_code"
}

# =============================================================================
# Test: Auth error case
# =============================================================================
@test "Should handle permission denied error fetching the asset-repository-provider" {
  set_np_mock "auth_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to fetch assets-repository provider"
  assert_contains "$output" "  🔒 Error: Permission denied"
}

# =============================================================================
# Test: Unknown error case
# =============================================================================
@test "Should handle unknown error fetching the asset-repository-provider" {
  set_np_mock "unknown_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to fetch assets-repository provider"
  assert_contains "$output" "  📋 Error details:"
  assert_contains "$output" "Unknown error fetching provider"
}

# =============================================================================
# Test: Empty results case
# =============================================================================
@test "Should fail if no asset-repository found" {
  set_np_mock "no_data.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ No S3 bucket found in assets-repository providers"
  assert_contains "$output" "  🤔 Found 0 provider(s), but none contain bucket information"
}

# =============================================================================
# Test: No providers found case
# =============================================================================
@test "Should fail when no asset provider is of type s3" {
  set_np_mock "no_bucket_data.json"

  run source "$SCRIPT_PATH"

  # TODO(federico.maleh) improve the how to fix instructions for these.
  # It should say: 1. you need an asset provider of type s3.
  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ No S3 bucket found in assets-repository providers"
  assert_contains "$output" "  🤔 Found 1 provider(s), but none contain bucket information"
  assert_contains "$output" "  📋 Providers found:"
  assert_contains "$output" "    • np provider read --id d397e46b-89b8-419d-ac14-2b483ace511c --format json"
}

# =============================================================================
# Test: S3 prefix extraction from asset URL
# =============================================================================
@test "Should extracts s3_prefix from asset.url with s3 format" {
  set_np_mock "success.json"

  run_cloudfront_setup

  local s3_prefix=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_s3_prefix')
  assert_equal "$s3_prefix" "/tools/automation/v1.0.0"
}

@test "Should extracts s3_prefix from asset.url with http format" {
  set_np_mock "success.json"

  # Override asset.url in context with https format
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://my-asset-bucket/tools/automation/v1.0.0"')

  run_cloudfront_setup

  local s3_prefix=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_s3_prefix')
  assert_equal "$s3_prefix" "/tools/automation/v1.0.0"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add distribution variables to TOFU_VARIABLES" {
  set_np_mock "success.json"

  run_cloudfront_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_bucket_name": "assets-bucket",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_resource_tags_json": {},
  "distribution_s3_prefix": "/tools/automation/v1.0.0"
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should add distribution_resource_tags_json to TOFU_VARIABLES" {
  set_np_mock "success.json"
  export RESOURCE_TAGS_JSON='{"Environment": "production", "Team": "platform"}'

  run_cloudfront_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_bucket_name": "assets-bucket",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_resource_tags_json": {"Environment": "production", "Team": "platform"},
  "distribution_s3_prefix": "/tools/automation/v1.0.0"
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  set_np_mock "success.json"

  run_cloudfront_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/distribution/cloudfront/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  set_np_mock "success.json"
  export MODULES_TO_USE="existing/module"

  run_cloudfront_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/distribution/cloudfront/modules"
}