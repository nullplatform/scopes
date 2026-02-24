#!/usr/bin/env bats
# =============================================================================
# Unit tests for provider/azure/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/provider/azure/setup_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/provider/azure/setup"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export AZURE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
  export AZURE_RESOURCE_GROUP="my-resource-group"
  export TOFU_PROVIDER_STORAGE_ACCOUNT="mytfstatestorage"
  export TOFU_PROVIDER_CONTAINER="tfstate"

  # Base tofu variables
  export TOFU_VARIABLES='{
    "application_slug": "automation",
    "scope_slug": "development-tools",
    "scope_id": "7"
  }'

  export TOFU_INIT_VARIABLES=""
  export MODULES_TO_USE=""
}

# =============================================================================
# Helper functions
# =============================================================================
run_azure_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Required environment variables
# =============================================================================
@test "Should fail when AZURE_SUBSCRIPTION_ID is not set" {
  unset AZURE_SUBSCRIPTION_ID

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ AZURE_SUBSCRIPTION_ID is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • AZURE_SUBSCRIPTION_ID"
}

@test "Should fail when AZURE_RESOURCE_GROUP is not set" {
  unset AZURE_RESOURCE_GROUP

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ AZURE_RESOURCE_GROUP is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • AZURE_RESOURCE_GROUP"
}

@test "Should fail when TOFU_PROVIDER_STORAGE_ACCOUNT is not set" {
  unset TOFU_PROVIDER_STORAGE_ACCOUNT

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ TOFU_PROVIDER_STORAGE_ACCOUNT is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • TOFU_PROVIDER_STORAGE_ACCOUNT"
}

@test "Should fail when TOFU_PROVIDER_CONTAINER is not set" {
  unset TOFU_PROVIDER_CONTAINER

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ TOFU_PROVIDER_CONTAINER is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • TOFU_PROVIDER_CONTAINER"
}

@test "Should report all the variables that are not set" {
  unset AZURE_SUBSCRIPTION_ID
  unset AZURE_RESOURCE_GROUP
  unset TOFU_PROVIDER_STORAGE_ACCOUNT
  unset TOFU_PROVIDER_CONTAINER

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ AZURE_SUBSCRIPTION_ID is missing"
  assert_contains "$output" "   ❌ AZURE_RESOURCE_GROUP is missing"
  assert_contains "$output" "   ❌ TOFU_PROVIDER_STORAGE_ACCOUNT is missing"
  assert_contains "$output" "   ❌ TOFU_PROVIDER_CONTAINER is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • AZURE_SUBSCRIPTION_ID"
  assert_contains "$output" "      • AZURE_RESOURCE_GROUP"
  assert_contains "$output" "      • TOFU_PROVIDER_STORAGE_ACCOUNT"
  assert_contains "$output" "      • TOFU_PROVIDER_CONTAINER"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add azure_provider field to TOFU_VARIABLES" {
  run_azure_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "azure_provider": {
    "subscription_id": "00000000-0000-0000-0000-000000000000",
    "resource_group": "my-resource-group",
    "storage_account": "mytfstatestorage",
    "container": "tfstate"
  },
  "provider_resource_tags_json": {}
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should add provider_resource_tags_json to TOFU_VARIABLES" {
  export RESOURCE_TAGS_JSON='{"Environment": "production", "Team": "platform"}'

  run_azure_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "azure_provider": {
    "subscription_id": "00000000-0000-0000-0000-000000000000",
    "resource_group": "my-resource-group",
    "storage_account": "mytfstatestorage",
    "container": "tfstate"
  },
  "provider_resource_tags_json": {"Environment": "production", "Team": "platform"}
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES - backend configuration
# =============================================================================
@test "Should add storage_account_name configuration to TOFU_INIT_VARIABLES" {
  run_azure_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=storage_account_name=mytfstatestorage"
}

@test "Should add container_name configuration to TOFU_INIT_VARIABLES" {
  run_azure_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=container_name=tfstate"
}

@test "Should add resource_group_name configuration to TOFU_INIT_VARIABLES" {
  run_azure_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=resource_group_name=my-resource-group"
}

@test "Should append to TOFU_INIT_VARIABLES when it previous settings are present" {
  export TOFU_INIT_VARIABLES="-var=existing=value"

  run_azure_setup

  assert_equal "$TOFU_INIT_VARIABLES" "-var=existing=value -backend-config=storage_account_name=mytfstatestorage -backend-config=container_name=tfstate -backend-config=resource_group_name=my-resource-group"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  run_azure_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/provider/azure/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  export MODULES_TO_USE="existing/module"

  run_azure_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/provider/azure/modules"
}
