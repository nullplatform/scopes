#!/usr/bin/env bats
# =============================================================================
# Unit tests for network/azure_dns/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/network/azure_dns/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/network/azure_dns/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"
  AZURE_MOCKS_DIR="$RESOURCES_DIR/azure_mocks"
  NP_MOCKS_DIR="$RESOURCES_DIR/np_mocks"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Add mock az and np to PATH (must be first)
  export PATH="$AZURE_MOCKS_DIR:$NP_MOCKS_DIR:$PATH"

  # Load context with public_dns_zone_name and public_dns_zone_resource_group_name
  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools", "id": "7"},
    "providers": {
      "cloud-providers": {
        "networking": {
          "public_dns_zone_resource_group_name": "my-resource-group",
          "public_dns_zone_name": "example.com"
        }
      }
    }
  }'

  # Initialize TOFU_VARIABLES with existing keys to verify script merges (not replaces)
  export TOFU_VARIABLES='{
    "application_slug": "automation",
    "scope_slug": "development-tools",
    "scope_id": "7"
  }'

  export MODULES_TO_USE=""

  # Set default np scope patch mock (success)
  export NP_MOCK_RESPONSE="$NP_MOCKS_DIR/scope/patch/success.json"
  export NP_MOCK_EXIT_CODE="0"
}

# =============================================================================
# Helper functions
# =============================================================================
run_azure_dns_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Required environment variables
# =============================================================================
@test "Should fail when public_dns_zone_name is not present in context" {
  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools"},
    "providers": {
      "cloud-providers": {
        "public_dns_zone_resource_group_name": "my-resource-group",
        "networking": {}
      }
    }
  }'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ public_dns_zone_name is not set in context"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Ensure there is an Azure cloud-provider configured at the correct NRN hierarchy level"
  assert_contains "$output" "    • Set the 'public_dns_zone_name' field with the Azure DNS zone name"
}

@test "Should fail when public_dns_zone_resource_group_name is not present in context" {
  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools"},
    "providers": {
      "cloud-providers": {
        "networking": {
          "public_dns_zone_name": "example.com"
        }
      }
    }
  }'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ public_dns_zone_resource_group_name is not set in context"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Ensure the Azure cloud-provider has 'public_dns_zone_resource_group_name' configured"
}

# =============================================================================
# Test: ResourceNotFound error
# =============================================================================
@test "Should fail if DNS zone does not exist" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/not_found.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to fetch Azure DNS zone information"
  assert_contains "$output" "  🔎 Error: DNS zone 'example.com' does not exist in resource group 'my-resource-group'"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The DNS zone name is incorrect or has a typo"
  assert_contains "$output" "    • The DNS zone was deleted"
  assert_contains "$output" "    • The resource group is incorrect"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Verify the DNS zone exists: az network dns zone list --resource-group my-resource-group"
  assert_contains "$output" "    • Update 'public_dns_zone_name' in the Azure cloud-provider configuration"
}

# =============================================================================
# Test: AccessDenied error
# =============================================================================
@test "Should fail if lacking permissions to read DNS zones" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/access_denied.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  🔒 Error: Permission denied when accessing Azure DNS"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The Azure credentials don't have DNS Zone read permissions"
  assert_contains "$output" "    • The service principal is missing the 'DNS Zone Contributor' role"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Check the Azure credentials are configured correctly"
  assert_contains "$output" "    • Ensure the service principal has 'DNS Zone Reader' or 'DNS Zone Contributor' role"
}

# =============================================================================
# Test: InvalidSubscription error
# =============================================================================
@test "Should fail if subscription is invalid" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/invalid_subscription.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  ⚠️  Error: Invalid subscription"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Verify the Azure subscription is correct"
  assert_contains "$output" "    • Check the service principal has access to the subscription"
}

# =============================================================================
# Test: Credentials error
# =============================================================================
@test "Should fail if Azure credentials are missing" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/credentials_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  🔑 Error: Azure credentials issue"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The nullplatform agent is not configured with Azure credentials"
  assert_contains "$output" "    • The service principal credentials have expired"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Configure Azure credentials in the nullplatform agent"
  assert_contains "$output" "    • Verify the service principal credentials are valid"
}

# =============================================================================
# Test: Unknown Azure DNS error
# =============================================================================
@test "Should handle unknown error getting the Azure DNS zone" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/unknown_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  📋 Error details:"
  assert_contains "$output" "Unknown error fetching Azure DNS zone."
}

# =============================================================================
# Test: Empty domain in response
# =============================================================================
@test "Should handle missing DNS zone name from response" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/empty_name.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to extract domain name from DNS zone response"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The DNS zone does not have a valid domain name configured"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Verify the DNS zone has a valid domain: az network dns zone show --name example.com --resource-group my-resource-group"
}

# =============================================================================
# Test: Scope patch error
# =============================================================================
@test "Should handle auth error updating scope domain" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/success.json"
  set_np_mock "$NP_MOCKS_DIR/scope/patch/auth_error.json" 1

  run source "$SCRIPT_PATH"

  assert_contains "$output" "   ❌ Failed to update scope domain"
  assert_contains "$output" "  🔒 Error: Permission denied"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The nullplatform API Key doesn't have 'Developer' permissions"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Ensure the API Key has 'Developer' permissions at the correct NRN hierarchy level"
}

@test "Should handle unknown error updating scope domain" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/success.json"
  set_np_mock "$NP_MOCKS_DIR/scope/patch/unknown_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to update scope domain"
  assert_contains "$output" "  📋 Error details:"
  assert_contains "$output" "Unknown error updating scope"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add network variables to TOFU_VARIABLES" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/success.json"

  run_azure_dns_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "network_dns_zone_name": "example.com",
  "network_domain": "example.com",
  "network_subdomain": "automation-development-tools"
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/success.json"

  run_azure_dns_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/network/azure_dns/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/success.json"
  export MODULES_TO_USE="existing/module"

  run_azure_dns_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/network/azure_dns/modules"
}
