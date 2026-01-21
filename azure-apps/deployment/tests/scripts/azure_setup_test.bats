#!/usr/bin/env bats
# =============================================================================
# Unit tests for azure_setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/scripts/azure_setup_test.bats
#
# Or run all tests:
#   bats tests/scripts/*.bats
# =============================================================================

# Setup - runs before each test
setup() {
  # Get the directory of the test file
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  SCRIPT_PATH="$PROJECT_DIR/scripts/azure_setup"

  # Set required environment variables with defaults
  export AZURE_SUBSCRIPTION_ID="test-subscription-id"
  export AZURE_RESOURCE_GROUP="test-resource-group"
  export AZURE_LOCATION="eastus"
  export TOFU_PROVIDER_STORAGE_ACCOUNT="tfstatestorage"
  export TOFU_PROVIDER_CONTAINER="tfstate"

  # Initialize TOFU_VARIABLES as empty JSON
  export TOFU_VARIABLES="{}"
  export TOFU_INIT_VARIABLES=""
  export RESOURCE_TAGS_JSON="{}"
}

# Teardown - runs after each test
teardown() {
  # Clean up exported variables
  unset AZURE_SUBSCRIPTION_ID
  unset AZURE_RESOURCE_GROUP
  unset AZURE_LOCATION
  unset TOFU_PROVIDER_STORAGE_ACCOUNT
  unset TOFU_PROVIDER_CONTAINER
  unset TOFU_VARIABLES
  unset TOFU_INIT_VARIABLES
  unset RESOURCE_TAGS_JSON
}

# =============================================================================
# Helper functions
# =============================================================================
run_azure_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Required environment variables - Error messages
# =============================================================================
@test "Should fail when AZURE_SUBSCRIPTION_ID is not set" {
  unset AZURE_SUBSCRIPTION_ID

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "🔍 Validating Azure provider configuration..."
  assert_contains "$output" "❌ AZURE_SUBSCRIPTION_ID is missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "• AZURE_SUBSCRIPTION_ID"
}

@test "Should fail when AZURE_RESOURCE_GROUP is not set" {
  unset AZURE_RESOURCE_GROUP

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ AZURE_RESOURCE_GROUP is missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• AZURE_RESOURCE_GROUP"
}

@test "Should fail when AZURE_LOCATION is not set" {
  unset AZURE_LOCATION

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ AZURE_LOCATION is missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• AZURE_LOCATION"
}

@test "Should fail when TOFU_PROVIDER_STORAGE_ACCOUNT is not set" {
  unset TOFU_PROVIDER_STORAGE_ACCOUNT

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ TOFU_PROVIDER_STORAGE_ACCOUNT is missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• TOFU_PROVIDER_STORAGE_ACCOUNT"
}

@test "Should fail when TOFU_PROVIDER_CONTAINER is not set" {
  unset TOFU_PROVIDER_CONTAINER

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ TOFU_PROVIDER_CONTAINER is missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• TOFU_PROVIDER_CONTAINER"
}

@test "Should fail when multiple variables are missing and list all of them" {
  unset AZURE_SUBSCRIPTION_ID
  unset AZURE_RESOURCE_GROUP
  unset TOFU_PROVIDER_STORAGE_ACCOUNT

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ AZURE_SUBSCRIPTION_ID is missing"
  assert_contains "$output" "❌ AZURE_RESOURCE_GROUP is missing"
  assert_contains "$output" "❌ TOFU_PROVIDER_STORAGE_ACCOUNT is missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• AZURE_SUBSCRIPTION_ID"
  assert_contains "$output" "• AZURE_RESOURCE_GROUP"
  assert_contains "$output" "• TOFU_PROVIDER_STORAGE_ACCOUNT"
}

# =============================================================================
# Test: Validation success messages
# =============================================================================
@test "Should display validation header message" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Validating Azure provider configuration..."
}

@test "Should display success message when all required variables are set" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✨ Azure provider configured successfully"
}

@test "Should display variable values when validation passes" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✅ AZURE_SUBSCRIPTION_ID=test-subscription-id"
  assert_contains "$output" "✅ AZURE_RESOURCE_GROUP=test-resource-group"
  assert_contains "$output" "✅ AZURE_LOCATION=eastus"
  assert_contains "$output" "✅ TOFU_PROVIDER_STORAGE_ACCOUNT=tfstatestorage"
  assert_contains "$output" "✅ TOFU_PROVIDER_CONTAINER=tfstate"
}

# =============================================================================
# Test: TOFU_VARIABLES generation
# =============================================================================
@test "Should generate TOFU_VARIABLES with azure_provider object" {
  run_azure_setup

  local expected_azure_provider='{
    "subscription_id": "test-subscription-id",
    "resource_group": "test-resource-group",
    "location": "eastus",
    "state_storage_account": "tfstatestorage",
    "state_container": "tfstate"
  }'

  local actual_azure_provider=$(echo "$TOFU_VARIABLES" | jq '.azure_provider')
  assert_json_equal "$actual_azure_provider" "$expected_azure_provider" "azure_provider"
}

@test "Should include provider_resource_tags_json in TOFU_VARIABLES" {
  export RESOURCE_TAGS_JSON='{"environment": "test", "team": "platform"}'

  run_azure_setup

  local expected_tags='{"environment": "test", "team": "platform"}'
  local actual_tags=$(echo "$TOFU_VARIABLES" | jq '.provider_resource_tags_json')
  assert_json_equal "$actual_tags" "$expected_tags" "provider_resource_tags_json"
}

@test "Should preserve existing TOFU_VARIABLES when adding azure_provider" {
  export TOFU_VARIABLES='{"existing_key": "existing_value"}'

  run_azure_setup

  local expected='{
    "existing_key": "existing_value",
    "azure_provider": {
      "subscription_id": "test-subscription-id",
      "resource_group": "test-resource-group",
      "location": "eastus",
      "state_storage_account": "tfstatestorage",
      "state_container": "tfstate"
    },
    "provider_resource_tags_json": {}
  }'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES generation
# =============================================================================
@test "Should generate TOFU_INIT_VARIABLES with backend config" {
  run_azure_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=storage_account_name=tfstatestorage"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=container_name=tfstate"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=resource_group_name=test-resource-group"
  assert_contains "$TOFU_INIT_VARIABLES" '-backend-config=key=azure-apps/${SCOPE_ID}/terraform.tfstate'
}

@test "Should preserve existing TOFU_INIT_VARIABLES" {
  export TOFU_INIT_VARIABLES="-backend-config=existing=value"

  run_azure_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=existing=value"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=storage_account_name=tfstatestorage"
}

# =============================================================================
# Test: Environment variable exports
# =============================================================================
@test "Should export TOFU_VARIABLES" {
  run_azure_setup

  assert_not_empty "$TOFU_VARIABLES" "TOFU_VARIABLES"
}

@test "Should export TOFU_INIT_VARIABLES" {
  run_azure_setup

  assert_not_empty "$TOFU_INIT_VARIABLES" "TOFU_INIT_VARIABLES"
}

@test "Should export AZURE_SUBSCRIPTION_ID" {
  run_azure_setup

  assert_equal "$AZURE_SUBSCRIPTION_ID" "test-subscription-id"
}

@test "Should export AZURE_RESOURCE_GROUP" {
  run_azure_setup

  assert_equal "$AZURE_RESOURCE_GROUP" "test-resource-group"
}

@test "Should export AZURE_LOCATION" {
  run_azure_setup

  assert_equal "$AZURE_LOCATION" "eastus"
}

# =============================================================================
# Test: MODULES_TO_USE handling
# =============================================================================
@test "Should set MODULES_TO_USE when modules directory exists" {
  # Create a temporary modules directory
  local temp_modules_dir=$(mktemp -d)
  mkdir -p "$temp_modules_dir/modules"

  # Create a modified script that uses our temp directory
  local temp_script=$(mktemp)
  sed "s|script_dir=.*|script_dir=\"$temp_modules_dir\"|" "$SCRIPT_PATH" > "$temp_script"

  export MODULES_TO_USE=""
  source "$temp_script"

  assert_contains "$MODULES_TO_USE" "$temp_modules_dir/modules"

  # Cleanup
  rm -rf "$temp_modules_dir"
  rm "$temp_script"
}

@test "Should append to existing MODULES_TO_USE when modules directory exists" {
  # Create a temporary modules directory
  local temp_modules_dir=$(mktemp -d)
  mkdir -p "$temp_modules_dir/modules"

  # Create a modified script that uses our temp directory
  local temp_script=$(mktemp)
  sed "s|script_dir=.*|script_dir=\"$temp_modules_dir\"|" "$SCRIPT_PATH" > "$temp_script"

  export MODULES_TO_USE="/existing/module"
  source "$temp_script"

  assert_contains "$MODULES_TO_USE" "/existing/module"
  assert_contains "$MODULES_TO_USE" "$temp_modules_dir/modules"

  # Cleanup
  rm -rf "$temp_modules_dir"
  rm "$temp_script"
}
