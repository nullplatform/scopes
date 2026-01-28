#!/usr/bin/env bats
# =============================================================================
# Unit tests for distribution/blob-cdn/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/distribution/blob-cdn/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/distribution/blob-cdn/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"
  MOCKS_DIR="$RESOURCES_DIR/np_mocks"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Add mock np to PATH (must be first)
  export PATH="$MOCKS_DIR:$PATH"

  # Load context with Azure-specific asset URL
  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools", "id": "7", "nrn": "organization=1:account=2:namespace=3:application=4:scope=7"},
    "asset": {"url": "https://mystaticstorage.blob.core.windows.net/$web/tools/automation/v1.0.0"}
  }'

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
run_blob_cdn_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Auth error case
# =============================================================================
@test "Should handle permission denied error fetching the asset-repository-provider" {
  set_np_mock "$MOCKS_DIR/asset_repository/auth_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to fetch assets-repository provider"
  assert_contains "$output" "  🔒 Error: Permission denied"
  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The nullplatform API Key doesn't have 'Ops' permissions at nrn: organization=1:account=2:namespace=3:application=4:scope=7"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    1. Ensure the API Key has 'Ops' permissions at the correct NRN hierarchy level"
}

# =============================================================================
# Test: Unknown error case
# =============================================================================
@test "Should handle unknown error fetching the asset-repository-provider" {
  set_np_mock "$MOCKS_DIR/asset_repository/unknown_error.json" 1

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
  set_np_mock "$MOCKS_DIR/asset_repository/no_data.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ No assets-repository provider of type Azure Blob Storage at nrn: organization=1:account=2:namespace=3:application=4:scope=7"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    1. Ensure there is an asset-repository provider of type Azure Blob Storage configured at the correct NRN hierarchy level"
}

# =============================================================================
# Test: No providers found case
# =============================================================================
@test "Should fail when no asset provider is of type Azure Blob Storage" {
  set_np_mock "$MOCKS_DIR/asset_repository_azure/no_storage_account_data.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ No assets-repository provider of type Azure Blob Storage at nrn: organization=1:account=2:namespace=3:application=4:scope=7"
  assert_contains "$output" "  🤔 Found 1 asset-repository provider(s), but none are configured for Azure Blob Storage."

  assert_contains "$output" "  📋 Verify the existing providers with the nullplatform CLI:"
  assert_contains "$output" "    • np provider read --id d397e46b-89b8-419d-ac14-2b483ace511c --format json"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    1. Ensure there is an asset-repository provider of type Azure Blob Storage configured at the correct NRN hierarchy level"
}

# =============================================================================
# Test: Blob prefix extraction from asset URL
# =============================================================================
@test "Should extract blob_prefix from asset.url with https format" {
  set_np_mock "$MOCKS_DIR/asset_repository_azure/success.json"

  run_blob_cdn_setup

  local blob_prefix=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')
  assert_equal "$blob_prefix" "/tools/automation/v1.0.0"
}

@test "Should use root prefix when asset.url has no path" {
  set_np_mock "$MOCKS_DIR/asset_repository_azure/success.json"

  # Override asset.url in context with no path
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "other://bucket"')

  run_blob_cdn_setup

  local blob_prefix=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')
  assert_equal "$blob_prefix" "/"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add distribution variables to TOFU_VARIABLES" {
  set_np_mock "$MOCKS_DIR/asset_repository_azure/success.json"

  run_blob_cdn_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_storage_account": "mystaticstorage",
  "distribution_container_name": "$web",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_blob_prefix": "/tools/automation/v1.0.0",
  "distribution_resource_tags_json": {}
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should add distribution_resource_tags_json to TOFU_VARIABLES" {
  set_np_mock "$MOCKS_DIR/asset_repository_azure/success.json"
  export RESOURCE_TAGS_JSON='{"Environment": "production", "Team": "platform"}'

  run_blob_cdn_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_storage_account": "mystaticstorage",
  "distribution_container_name": "$web",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_blob_prefix": "/tools/automation/v1.0.0",
  "distribution_resource_tags_json": {"Environment": "production", "Team": "platform"}
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  set_np_mock "$MOCKS_DIR/asset_repository_azure/success.json"

  run_blob_cdn_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/distribution/blob-cdn/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  set_np_mock "$MOCKS_DIR/asset_repository_azure/success.json"
  export MODULES_TO_USE="existing/module"

  run_blob_cdn_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/distribution/blob-cdn/modules"
}
