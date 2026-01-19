#!/usr/bin/env bats
# =============================================================================
# Integration test: Azure BlobCDN + Azure DNS Lifecycle
#
# Tests the full lifecycle of a static frontend deployment on Azure:
#   1. Create infrastructure (CDN endpoint + DNS CNAME record)
#   2. Verify all resources are configured correctly
#   3. Destroy infrastructure
#   4. Verify all resources are removed
# =============================================================================

# =============================================================================
# Test Constants
# =============================================================================
# Expected values derived from context_azure.json and terraform variables

# CDN variables (distribution/azure_blob_cdn/modules/variables.tf)
TEST_DISTRIBUTION_STORAGE_ACCOUNT="assetsaccount"                              # distribution_storage_account
TEST_DISTRIBUTION_CONTAINER="assets"                                           # distribution_container
TEST_DISTRIBUTION_S3_PREFIX="/tools/automation/v1.0.0"                         # distribution_s3_prefix
TEST_DISTRIBUTION_APP_NAME="automation-development-tools-7"                    # distribution_app_name

# DNS variables (network/azure_dns/modules/variables.tf)
TEST_NETWORK_DOMAIN="frontend.publicdomain.com"                                # network_domain
TEST_NETWORK_SUBDOMAIN="automation-development-tools"                          # network_subdomain
TEST_NETWORK_FULL_DOMAIN="automation-development-tools.frontend.publicdomain.com"  # computed

# Azure resource identifiers
TEST_SUBSCRIPTION_ID="mock-subscription-id"
TEST_RESOURCE_GROUP="test-resource-group"
TEST_DNS_ZONE_RESOURCE_GROUP="dns-resource-group"

# =============================================================================
# Test Setup
# =============================================================================

setup_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  source "${PROJECT_ROOT}/testing/assertions.sh"
  integration_setup --cloud-provider azure

  clear_mocks

  # Pre-create Azure DNS zone in the mock server (required for data source lookup)
  echo "Creating test prerequisites in Azure Mock..."

  # Create DNS zone via REST API
  azure_mock_put "/subscriptions/${TEST_SUBSCRIPTION_ID}/resourceGroups/${TEST_DNS_ZONE_RESOURCE_GROUP}/providers/Microsoft.Network/dnszones/${TEST_NETWORK_DOMAIN}" \
    '{"location": "global", "tags": {}}' >/dev/null 2>&1 || true

  # Create Storage Account via REST API (for data source lookup)
  azure_mock_put "/subscriptions/${TEST_SUBSCRIPTION_ID}/resourceGroups/${TEST_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${TEST_DISTRIBUTION_STORAGE_ACCOUNT}" \
    '{"location": "eastus", "kind": "StorageV2", "sku": {"name": "Standard_LRS", "tier": "Standard"}}' >/dev/null 2>&1 || true

  export TEST_SUBSCRIPTION_ID
  export TEST_RESOURCE_GROUP
  export TEST_DNS_ZONE_RESOURCE_GROUP
}

teardown_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  clear_mocks
  integration_teardown
}

setup() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  source "${PROJECT_ROOT}/testing/assertions.sh"
  source "${BATS_TEST_DIRNAME}/cdn_assertions.bash"
  source "${BATS_TEST_DIRNAME}/dns_assertions.bash"

  clear_mocks
  load_context "frontend/deployment/tests/resources/context_azure.json"

  # Export environment variables
  export NETWORK_LAYER="azure_dns"
  export DISTRIBUTION_LAYER="blob-cdn"
  export TOFU_PROVIDER="azure"
  export SERVICE_PATH="$INTEGRATION_MODULE_ROOT/frontend"
  export CUSTOM_TOFU_MODULES="$INTEGRATION_MODULE_ROOT/testing/azure-mock-provider"

  # Azure provider required environment variables
  export AZURE_SUBSCRIPTION_ID="$TEST_SUBSCRIPTION_ID"
  export AZURE_RESOURCE_GROUP="$TEST_RESOURCE_GROUP"
  # Use Azurite's storage account for backend (like LocalStack for AWS)
  export TOFU_PROVIDER_STORAGE_ACCOUNT="${AZURITE_ACCOUNT_NAME:-devstoreaccount1}"
  export TOFU_PROVIDER_CONTAINER="tfstate"

  # Setup API mocks for np CLI calls
  local mocks_dir="frontend/deployment/tests/integration/mocks/"
  mock_request "GET" "/category" "$mocks_dir/asset_repository/category.json"
  mock_request "GET" "/provider_specification" "$mocks_dir/asset_repository/list_provider_spec.json"
  mock_request "GET" "/provider" "$mocks_dir/azure_asset_repository/list_provider.json"
  mock_request "GET" "/provider/azure-blob-asset-repository-id" "$mocks_dir/azure_asset_repository/get_provider.json"
  mock_request "PATCH" "/scope/7" "$mocks_dir/scope/patch.json"
}

# =============================================================================
# Test: Create Infrastructure
# =============================================================================

#@test "create infrastructure deploys Azure CDN and DNS resources" {
#  run_workflow "frontend/deployment/workflows/initial.yaml"
#
#  assert_azure_cdn_configured \
#    "$TEST_DISTRIBUTION_APP_NAME" \
#    "$TEST_DISTRIBUTION_STORAGE_ACCOUNT" \
#    "$TEST_SUBSCRIPTION_ID" \
#    "$TEST_RESOURCE_GROUP"
#
#  assert_azure_dns_configured \
#    "$TEST_NETWORK_SUBDOMAIN" \
#    "$TEST_NETWORK_DOMAIN" \
#    "$TEST_SUBSCRIPTION_ID" \
#    "$TEST_DNS_ZONE_RESOURCE_GROUP"
#}

# =============================================================================
# Test: Destroy Infrastructure
# =============================================================================

#@test "destroy infrastructure removes Azure CDN and DNS resources" {
#  run_workflow "frontend/deployment/workflows/delete.yaml"
#
#  assert_azure_cdn_not_configured \
#    "$TEST_DISTRIBUTION_APP_NAME" \
#    "$TEST_SUBSCRIPTION_ID" \
#    "$TEST_RESOURCE_GROUP"
#
#  assert_azure_dns_not_configured \
#    "$TEST_NETWORK_SUBDOMAIN" \
#    "$TEST_NETWORK_DOMAIN" \
#    "$TEST_SUBSCRIPTION_ID" \
#    "$TEST_DNS_ZONE_RESOURCE_GROUP"
#}
