#!/usr/bin/env bats
# =============================================================================
# Unit tests for traffic_management script
#
# Requirements:
#   - bats-core: brew install bats-core
#
# Run tests:
#   bats tests/scripts/traffic_management_test.bats
#
# Or run all tests:
#   bats tests/scripts/*.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  SCRIPT_PATH="$PROJECT_DIR/scripts/traffic_management"
  MOCKS_DIR="$PROJECT_DIR/tests/resources/mocks"

  # Add mock az to PATH (must be first to override real az)
  export PATH="$MOCKS_DIR:$PATH"

  # Create a temp file to capture az calls
  export AZ_CALL_LOG=$(mktemp)
  export AZ_MOCK_EXIT_CODE=0

  # Set required environment variables (from azure_setup)
  export ARM_CLIENT_ID="test-client-id"
  export ARM_CLIENT_SECRET="test-client-secret"
  export ARM_TENANT_ID="test-tenant-id"
  export ARM_SUBSCRIPTION_ID="test-subscription-id"
  export AZURE_RESOURCE_GROUP="test-resource-group"

  # Set required environment variables (from build_context)
  export APP_NAME="test-app"
  export STAGING_TRAFFIC_PERCENT="0"
}

# Teardown - runs after each test
teardown() {
  rm -f "$AZ_CALL_LOG"
  unset AZ_CALL_LOG
  unset AZ_MOCK_EXIT_CODE
  unset ARM_CLIENT_ID
  unset ARM_CLIENT_SECRET
  unset ARM_TENANT_ID
  unset ARM_SUBSCRIPTION_ID
  unset AZURE_RESOURCE_GROUP
  unset APP_NAME
  unset STAGING_TRAFFIC_PERCENT
}

# =============================================================================
# Test: Output messages
# =============================================================================
@test "Should display routing header message" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Configuring traffic routing..."
}

@test "Should display success message" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Traffic routing updated successfully"
}

# =============================================================================
# Test: Azure login
# =============================================================================
@test "Should login to Azure with service principal credentials" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$AZ_CALL_LOG")
  assert_contains "$calls" "login --service-principal --username test-client-id --password test-client-secret --tenant test-tenant-id --output none"
}

@test "Should set the Azure subscription" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$AZ_CALL_LOG")
  assert_contains "$calls" "account set --subscription test-subscription-id"
}

@test "Should fail when az login fails" {
  export AZ_MOCK_EXIT_CODE=1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
}

# =============================================================================
# Test: Traffic routing - Clear (0%)
# =============================================================================
@test "Should clear traffic routing when STAGING_TRAFFIC_PERCENT is 0" {
  export STAGING_TRAFFIC_PERCENT="0"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$AZ_CALL_LOG")
  assert_contains "$calls" "webapp traffic-routing clear --resource-group test-resource-group --name test-app"
}

@test "Should display clearing message when STAGING_TRAFFIC_PERCENT is 0" {
  export STAGING_TRAFFIC_PERCENT="0"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Clearing traffic routing for test-app (100% to production)"
}

@test "Should default STAGING_TRAFFIC_PERCENT to 0 and clear routing" {
  unset STAGING_TRAFFIC_PERCENT

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Clearing traffic routing for test-app (100% to production)"
}

# =============================================================================
# Test: Traffic routing - Set (> 0%)
# =============================================================================
@test "Should set traffic routing when STAGING_TRAFFIC_PERCENT is greater than 0" {
  export STAGING_TRAFFIC_PERCENT="25"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$AZ_CALL_LOG")
  assert_contains "$calls" "webapp traffic-routing set --resource-group test-resource-group --name test-app --distribution staging=25"
}

@test "Should display correct percentages when setting traffic to 25%" {
  export STAGING_TRAFFIC_PERCENT="25"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Setting traffic for test-app: production=75% staging=25%"
}

@test "Should display correct percentages when setting traffic to 50%" {
  export STAGING_TRAFFIC_PERCENT="50"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Setting traffic for test-app: production=50% staging=50%"
}

@test "Should display correct percentages when setting traffic to 100%" {
  export STAGING_TRAFFIC_PERCENT="100"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Setting traffic for test-app: production=0% staging=100%"
}

# =============================================================================
# Test: Missing environment variables
# =============================================================================
@test "Should fail when ARM_CLIENT_ID is not set" {
  unset ARM_CLIENT_ID

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
}

@test "Should fail when ARM_CLIENT_SECRET is not set" {
  unset ARM_CLIENT_SECRET

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
}

@test "Should fail when ARM_TENANT_ID is not set" {
  unset ARM_TENANT_ID

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
}

@test "Should fail when ARM_SUBSCRIPTION_ID is not set" {
  unset ARM_SUBSCRIPTION_ID

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
}

@test "Should fail when APP_NAME is not set" {
  unset APP_NAME

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
}

@test "Should fail when AZURE_RESOURCE_GROUP is not set" {
  unset AZURE_RESOURCE_GROUP

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
}
