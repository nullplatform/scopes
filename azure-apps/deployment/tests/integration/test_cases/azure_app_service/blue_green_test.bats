#!/usr/bin/env bats
# =============================================================================
# Integration test: Azure App Service Blue-Green Deployment
#
# Tests the blue-green deployment lifecycle:
#   1. Initial deployment (no staging slot)
#   2. Blue-green deployment (creates staging slot with 0% traffic)
#   3. Finalize deployment (swap slots, disable staging)
# =============================================================================

# =============================================================================
# Test Constants
# =============================================================================
TEST_APP_NAME="tools-automation-development-tools-7"
TEST_PLAN_NAME="tools-automation-development-tools-7-plan"
TEST_SLOT_NAME="staging"

# Azure resource identifiers
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

  echo "Setting up blue-green deployment tests..."

  export TEST_APP_NAME
  export TEST_PLAN_NAME
  export TEST_SLOT_NAME
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

  # Use mock storage account for backend
  export TOFU_PROVIDER_STORAGE_ACCOUNT="devstoreaccount1"
  export TOFU_PROVIDER_CONTAINER="tfstate"

  # Setup API mocks for np CLI calls
  local mocks_dir="azure-apps/deployment/tests/integration/mocks/"
  mock_request "PATCH" "/scope/7" "$mocks_dir/scope/patch.json"

  # Ensure tfstate container exists in azure-mock
  curl -s -X PUT "${AZURE_MOCK_ENDPOINT}/tfstate?restype=container" \
    -H "Host: devstoreaccount1.blob.core.windows.net" \
    -H "x-ms-version: 2021-06-08" >/dev/null 2>&1 || true
}

# =============================================================================
# Test: Initial Deployment (no staging slot)
# =============================================================================

@test "Should create App Service without staging slot on initial deployment" {
  run_workflow "azure-apps/deployment/workflows/initial.yaml"

  # Verify App Service is created
  assert_azure_app_service_configured \
    "$TEST_APP_NAME" \
    "$TEST_SUBSCRIPTION_ID" \
    "$TEST_RESOURCE_GROUP" \
    "$TEST_EXPECTED_SKU"

  # Verify staging slot does NOT exist
  assert_deployment_slot_not_exists \
    "$TEST_APP_NAME" \
    "$TEST_SLOT_NAME" \
    "$TEST_SUBSCRIPTION_ID" \
    "$TEST_RESOURCE_GROUP"
}

# =============================================================================
# Test: Blue-Green Deployment (creates staging slot)
# =============================================================================

@test "Should create staging slot on blue_green deployment" {
  # First run initial to create base infrastructure
  run_workflow "azure-apps/deployment/workflows/initial.yaml"

  # Then run blue_green to create staging slot
  run_workflow "azure-apps/deployment/workflows/blue_green.yaml"

  # Verify App Service with staging slot is created
  assert_azure_app_service_with_slot_configured \
    "$TEST_APP_NAME" \
    "$TEST_SUBSCRIPTION_ID" \
    "$TEST_RESOURCE_GROUP" \
    "$TEST_EXPECTED_SKU" \
    "$TEST_SLOT_NAME"
}

# =============================================================================
# Test: Switch Traffic
# =============================================================================

@test "Should maintain staging slot with traffic percentage from context on switch_traffic deployment" {
  # Setup: Create infrastructure with staging slot
  run_workflow "azure-apps/deployment/workflows/initial.yaml"
  run_workflow "azure-apps/deployment/workflows/blue_green.yaml"

  # Modify context to have desired_switched_traffic = 50
  export CONTEXT=$(echo "$CONTEXT" | jq '.deployment.strategy_data.desired_switched_traffic = 50')

  # Run switch_traffic workflow
  run_workflow "azure-apps/deployment/workflows/switch_traffic.yaml"

  # Verify staging slot still exists (traffic routing is via Azure CLI, not terraform state)
  assert_azure_app_service_with_slot_configured \
    "$TEST_APP_NAME" \
    "$TEST_SUBSCRIPTION_ID" \
    "$TEST_RESOURCE_GROUP" \
    "$TEST_EXPECTED_SKU" \
    "$TEST_SLOT_NAME"
}

# =============================================================================
# Test: Destroy Blue-Green Infrastructure
# =============================================================================

@test "Should remove App Service and all slots on delete" {
  # Setup: Create infrastructure with staging slot
  run_workflow "azure-apps/deployment/workflows/initial.yaml"
  run_workflow "azure-apps/deployment/workflows/blue_green.yaml"

  # Destroy all infrastructure
  run_workflow "azure-apps/deployment/workflows/delete.yaml"

  # Verify everything is removed
  assert_azure_app_service_not_configured \
    "$TEST_APP_NAME" \
    "$TEST_SUBSCRIPTION_ID" \
    "$TEST_RESOURCE_GROUP"

  # Staging slot should also be gone (implicitly deleted with app)
  assert_deployment_slot_not_exists \
    "$TEST_APP_NAME" \
    "$TEST_SLOT_NAME" \
    "$TEST_SUBSCRIPTION_ID" \
    "$TEST_RESOURCE_GROUP"
}
