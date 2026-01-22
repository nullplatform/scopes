#!/usr/bin/env bats
# =============================================================================
# Integration test: Azure App Service Lifecycle
#
# Tests the full lifecycle of an Azure App Service deployment:
#   1. Create infrastructure (App Service Plan + Linux Web App)
#   2. Verify all resources are configured correctly
#   3. Destroy infrastructure
#   4. Verify all resources are removed
# =============================================================================

# =============================================================================
# Test Constants
# =============================================================================
# Expected values derived from context_integration.json
# App name is generated: {namespace_slug}-{application_slug}-{scope_slug}-{scope_id}
# From context: tools-automation-development-tools-7

TEST_APP_NAME="tools-automation-development-tools-7"
TEST_PLAN_NAME="tools-automation-development-tools-7-plan"

# Azure resource identifiers (from context providers.cloud-providers.azure)
TEST_SUBSCRIPTION_ID="mock-subscription-id"
TEST_RESOURCE_GROUP="test-resource-group"
TEST_LOCATION="eastus"

# Expected SKU based on memory=4 GB from context
TEST_EXPECTED_SKU="S2"

# =============================================================================
# Test Setup
# =============================================================================

setup_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  source "${PROJECT_ROOT}/testing/assertions.sh"
  integration_setup --cloud-provider azure

  clear_mocks

  echo "Creating test prerequisites in Azure Mock..."

  # Export test variables for use in tests
  export TEST_APP_NAME
  export TEST_PLAN_NAME
  export TEST_SUBSCRIPTION_ID
  export TEST_RESOURCE_GROUP
  export TEST_LOCATION
  export TEST_EXPECTED_SKU
}

teardown_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  clear_mocks
  integration_teardown
}

setup() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  source "${PROJECT_ROOT}/testing/assertions.sh"
  source "${BATS_TEST_DIRNAME}/app_service_assertions.bash"

  clear_mocks
  load_context "azure-apps/deployment/tests/integration/resources/context_integration.json"

  # Export environment variables for workflow execution
  export SERVICE_PATH="$INTEGRATION_MODULE_ROOT/azure-apps"
  export CUSTOM_TOFU_MODULES="$INTEGRATION_MODULE_ROOT/testing/azure-mock-provider"

  # Azure provider required environment variables
  export AZURE_SUBSCRIPTION_ID="$TEST_SUBSCRIPTION_ID"
  export AZURE_RESOURCE_GROUP="$TEST_RESOURCE_GROUP"
  export AZURE_LOCATION="$TEST_LOCATION"

  # Use mock storage account for backend (handled by azure-mock)
  export TOFU_PROVIDER_STORAGE_ACCOUNT="devstoreaccount1"
  export TOFU_PROVIDER_CONTAINER="tfstate"

  # Setup API mocks for np CLI calls
  local mocks_dir="azure-apps/deployment/tests/integration/mocks/"
  mock_request "PATCH" "/scope/7" "$mocks_dir/scope/patch.json"

  # Ensure tfstate container exists in azure-mock for Terraform backend
  curl -s -X PUT "${AZURE_MOCK_ENDPOINT}/tfstate?restype=container" \
    -H "Host: devstoreaccount1.blob.core.windows.net" \
    -H "x-ms-version: 2021-06-08" >/dev/null 2>&1 || true
}

# =============================================================================
# Test: Create Infrastructure
# =============================================================================

@test "create infrastructure deploys Azure App Service resources" {
  run_workflow "azure-apps/deployment/workflows/initial.yaml"

  assert_azure_app_service_configured \
    "$TEST_APP_NAME" \
    "$TEST_SUBSCRIPTION_ID" \
    "$TEST_RESOURCE_GROUP" \
    "$TEST_EXPECTED_SKU"
}

# =============================================================================
# Test: Destroy Infrastructure
# =============================================================================

@test "destroy infrastructure removes Azure App Service resources" {
  run_workflow "azure-apps/deployment/workflows/delete.yaml"

  assert_azure_app_service_not_configured \
    "$TEST_APP_NAME" \
    "$TEST_SUBSCRIPTION_ID" \
    "$TEST_RESOURCE_GROUP"
}
