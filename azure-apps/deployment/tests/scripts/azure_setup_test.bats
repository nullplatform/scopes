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

  # Load CONTEXT from test resources
  export CONTEXT=$(cat "$PROJECT_DIR/tests/resources/context.json")

  # Set required environment variables with defaults
  export TOFU_PROVIDER_STORAGE_ACCOUNT="tfstatestorage"
  export TOFU_PROVIDER_CONTAINER="tfstate"
  export ARM_CLIENT_SECRET="test-client-secret"

  # Initialize TOFU_VARIABLES as empty JSON
  export TOFU_VARIABLES="{}"
  export TOFU_INIT_VARIABLES=""
  export RESOURCE_TAGS_JSON="{}"

  # STATE_KEY is normally set by build_context
  export STATE_KEY="azure-apps/7/terraform.tfstate"
}

# Teardown - runs after each test
teardown() {
  # Clean up exported variables
  unset CONTEXT
  unset ARM_SUBSCRIPTION_ID
  unset ARM_CLIENT_ID
  unset ARM_TENANT_ID
  unset ARM_CLIENT_SECRET
  unset AZURE_RESOURCE_GROUP
  unset AZURE_LOCATION
  unset TOFU_PROVIDER_STORAGE_ACCOUNT
  unset TOFU_PROVIDER_CONTAINER
  unset TOFU_VARIABLES
  unset TOFU_INIT_VARIABLES
  unset RESOURCE_TAGS_JSON
  unset STATE_KEY
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

@test "Should fail when ARM_CLIENT_SECRET is not set" {
  unset ARM_CLIENT_SECRET

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ARM_CLIENT_SECRET is missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• ARM_CLIENT_SECRET"
}

@test "Should fail when multiple env variables are missing and list all of them" {
  unset TOFU_PROVIDER_STORAGE_ACCOUNT
  unset TOFU_PROVIDER_CONTAINER
  unset ARM_CLIENT_SECRET

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ TOFU_PROVIDER_STORAGE_ACCOUNT is missing"
  assert_contains "$output" "❌ TOFU_PROVIDER_CONTAINER is missing"
  assert_contains "$output" "❌ ARM_CLIENT_SECRET is missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• TOFU_PROVIDER_STORAGE_ACCOUNT"
  assert_contains "$output" "• TOFU_PROVIDER_CONTAINER"
  assert_contains "$output" "• ARM_CLIENT_SECRET"
}

# =============================================================================
# Test: Context-derived variables - Validation
# =============================================================================
@test "Should fail when ARM_SUBSCRIPTION_ID cannot be resolved from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["cloud-providers"].authentication.subscription_id)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ARM_SUBSCRIPTION_ID could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Verify that you have an Azure cloud provider linked to this scope."
  assert_contains "$output" "• subscription_id"
}

@test "Should fail when ARM_CLIENT_ID cannot be resolved from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["cloud-providers"].authentication.client_id)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ARM_CLIENT_ID could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Verify that you have an Azure cloud provider linked to this scope."
  assert_contains "$output" "• client_id"
}

@test "Should fail when ARM_TENANT_ID cannot be resolved from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["cloud-providers"].authentication.tenant_id)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ARM_TENANT_ID could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Verify that you have an Azure cloud provider linked to this scope."
  assert_contains "$output" "• tenant_id"
}

@test "Should fail when AZURE_RESOURCE_GROUP cannot be resolved from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["cloud-providers"].networking.public_dns_zone_resource_group_name)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ AZURE_RESOURCE_GROUP could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Verify that you have an Azure cloud provider linked to this scope."
  assert_contains "$output" "• public_dns_zone_resource_group_name"
}

@test "Should fail when cloud-providers section is missing from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["cloud-providers"])')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ARM_SUBSCRIPTION_ID could not be resolved from providers"
  assert_contains "$output" "❌ ARM_CLIENT_ID could not be resolved from providers"
  assert_contains "$output" "❌ ARM_TENANT_ID could not be resolved from providers"
  assert_contains "$output" "❌ AZURE_RESOURCE_GROUP could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Verify that you have an Azure cloud provider linked to this scope."
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
  assert_contains "$output" "✅ TOFU_PROVIDER_STORAGE_ACCOUNT=tfstatestorage"
  assert_contains "$output" "✅ TOFU_PROVIDER_CONTAINER=tfstate"
}

@test "Should redact variable value when name contains secret" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✅ ARM_CLIENT_SECRET=REDACTED"
  [[ "$output" != *"test-client-secret"* ]]
}

# =============================================================================
# Test: Context value extraction
# =============================================================================
@test "Should extract ARM_SUBSCRIPTION_ID from context" {
  run_azure_setup

  assert_equal "$ARM_SUBSCRIPTION_ID" "test-subscription-id"
}

@test "Should extract ARM_CLIENT_ID from context" {
  run_azure_setup

  assert_equal "$ARM_CLIENT_ID" "test-client-id"
}

@test "Should extract ARM_TENANT_ID from context" {
  run_azure_setup

  assert_equal "$ARM_TENANT_ID" "test-tenant-id"
}

@test "Should extract AZURE_RESOURCE_GROUP from context" {
  run_azure_setup

  assert_equal "$AZURE_RESOURCE_GROUP" "test-resource-group"
}

@test "Should set AZURE_LOCATION to australiaeast" {
  run_azure_setup

  assert_equal "$AZURE_LOCATION" "australiaeast"
}

# =============================================================================
# Test: TOFU_VARIABLES generation
# =============================================================================
@test "Should generate TOFU_VARIABLES with resource_group_name" {
  run_azure_setup

  local actual_value=$(echo "$TOFU_VARIABLES" | jq -r '.resource_group_name')
  assert_equal "$actual_value" "test-resource-group"
}

@test "Should generate TOFU_VARIABLES with location" {
  run_azure_setup

  local actual_value=$(echo "$TOFU_VARIABLES" | jq -r '.location')
  assert_equal "$actual_value" "australiaeast"
}

@test "Should include resource_tags in TOFU_VARIABLES" {
  export RESOURCE_TAGS_JSON='{"environment": "test", "team": "platform"}'

  run_azure_setup

  local expected_tags='{"environment": "test", "team": "platform"}'
  local actual_tags=$(echo "$TOFU_VARIABLES" | jq '.resource_tags')
  assert_json_equal "$actual_tags" "$expected_tags" "resource_tags"
}

@test "Should preserve existing TOFU_VARIABLES when adding azure variables" {
  export TOFU_VARIABLES='{"existing_key": "existing_value"}'

  run_azure_setup

  local expected='{
    "existing_key": "existing_value",
    "resource_group_name": "test-resource-group",
    "location": "australiaeast",
    "resource_tags": {}
  }'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES generation
# =============================================================================
@test "Should generate TOFU_INIT_VARIABLES with backend config" {
  export STATE_KEY="azure-apps/42/terraform.tfstate"

  run_azure_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=storage_account_name=tfstatestorage"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=container_name=tfstate"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=resource_group_name=test-resource-group"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=key=azure-apps/42/terraform.tfstate"
}

@test "Should preserve existing TOFU_INIT_VARIABLES" {
  export TOFU_INIT_VARIABLES="-backend-config=existing=value"

  run_azure_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=existing=value"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=storage_account_name=tfstatestorage"
}

@test "Should use STATE_KEY from build_context in backend config" {
  export STATE_KEY="azure-apps/99/terraform.tfstate"

  run_azure_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=key=azure-apps/99/terraform.tfstate"
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

@test "Should export ARM_SUBSCRIPTION_ID" {
  run_azure_setup

  assert_equal "$ARM_SUBSCRIPTION_ID" "test-subscription-id"
}

@test "Should export ARM_CLIENT_ID" {
  run_azure_setup

  assert_equal "$ARM_CLIENT_ID" "test-client-id"
}

@test "Should export ARM_TENANT_ID" {
  run_azure_setup

  assert_equal "$ARM_TENANT_ID" "test-tenant-id"
}

@test "Should export ARM_CLIENT_SECRET" {
  run_azure_setup

  assert_equal "$ARM_CLIENT_SECRET" "test-client-secret"
}

@test "Should export AZURE_RESOURCE_GROUP" {
  run_azure_setup

  assert_equal "$AZURE_RESOURCE_GROUP" "test-resource-group"
}

@test "Should export AZURE_LOCATION" {
  run_azure_setup

  assert_equal "$AZURE_LOCATION" "australiaeast"
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
