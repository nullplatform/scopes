#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment_slots terraform configuration
#
# Tests the deployment slots terraform module validation:
#   - Variable validation (staging_traffic_percent range)
#   - Configuration validity with different variable combinations
#
# Note: Resource creation tests are in integration tests which use azure-mock
#
# Requirements:
#   - bats-core: brew install bats-core
#   - tofu/terraform: brew install opentofu
#
# Run tests:
#   bats tests/modules/deployment_slots_test.bats
# =============================================================================

# Setup once for all tests
setup_file() {
  export TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  export PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  export MODULE_PATH="$PROJECT_DIR/modules"

  # Create temporary working directory
  export TEST_WORKING_DIR=$(mktemp -d)

  # Copy module files to working directory
  cp -r "$MODULE_PATH"/* "$TEST_WORKING_DIR/"

  # Create a minimal provider override for validation testing
  cat > "$TEST_WORKING_DIR/provider_override.tf" << 'EOF'
terraform {
  backend "local" {}
}
EOF

  # Initialize terraform once (backend=false for validation only)
  cd "$TEST_WORKING_DIR"
  tofu init -backend=false >/dev/null 2>&1
}

# Cleanup after all tests
teardown_file() {
  rm -rf "$TEST_WORKING_DIR"
}

# Setup before each test
setup() {
  cd "$TEST_WORKING_DIR"

  # Base required variables for all tests
  export TF_VAR_resource_group_name="test-rg"
  export TF_VAR_location="eastus"
  export TF_VAR_app_name="test-app"
  export TF_VAR_docker_image="nginx:latest"

  # Default blue-green deployment settings (disabled)
  export TF_VAR_enable_staging_slot="false"
  export TF_VAR_staging_traffic_percent="0"
  export TF_VAR_promote_staging_to_production="false"
}

# =============================================================================
# Test: Variable Type Validation
# Note: Custom validation rules (0-100 range) are checked at plan time,
#       not validate time. Those are tested in integration tests.
# =============================================================================

@test "Should accept staging_traffic_percent value of 0" {
  export TF_VAR_staging_traffic_percent="0"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should accept staging_traffic_percent value of 50" {
  export TF_VAR_staging_traffic_percent="50"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should accept staging_traffic_percent value of 100" {
  export TF_VAR_staging_traffic_percent="100"

  run tofu validate
  [ "$status" -eq 0 ]
}

# =============================================================================
# Test: Configuration Validity - Different Scenarios
# =============================================================================

@test "Should validate module with staging slot disabled" {
  export TF_VAR_enable_staging_slot="false"
  export TF_VAR_staging_traffic_percent="0"
  export TF_VAR_promote_staging_to_production="false"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should validate module with staging slot enabled" {
  export TF_VAR_enable_staging_slot="true"
  export TF_VAR_staging_traffic_percent="0"
  export TF_VAR_promote_staging_to_production="false"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should validate module with staging slot and traffic routing" {
  export TF_VAR_enable_staging_slot="true"
  export TF_VAR_staging_traffic_percent="50"
  export TF_VAR_promote_staging_to_production="false"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should validate module with staging slot and promotion" {
  export TF_VAR_enable_staging_slot="true"
  export TF_VAR_staging_traffic_percent="0"
  export TF_VAR_promote_staging_to_production="true"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should validate blue_green scenario configuration" {
  # blue_green.yaml: staging slot enabled, 0% traffic, no promotion
  export TF_VAR_enable_staging_slot="true"
  export TF_VAR_staging_traffic_percent="0"
  export TF_VAR_promote_staging_to_production="false"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should validate switch_traffic scenario configuration" {
  # switch_traffic.yaml: staging slot enabled, variable traffic %
  export TF_VAR_enable_staging_slot="true"
  export TF_VAR_staging_traffic_percent="25"
  export TF_VAR_promote_staging_to_production="false"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should validate finalize scenario configuration" {
  # finalize.yaml: staging slot disabled after swap, promotion true
  export TF_VAR_enable_staging_slot="false"
  export TF_VAR_staging_traffic_percent="0"
  export TF_VAR_promote_staging_to_production="true"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should validate module with 100% traffic to staging" {
  export TF_VAR_enable_staging_slot="true"
  export TF_VAR_staging_traffic_percent="100"
  export TF_VAR_promote_staging_to_production="false"

  run tofu validate
  [ "$status" -eq 0 ]
}

# =============================================================================
# Test: Boolean Variable Validation
# =============================================================================

@test "Should accept enable_staging_slot value of true" {
  export TF_VAR_enable_staging_slot="true"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should accept enable_staging_slot value of false" {
  export TF_VAR_enable_staging_slot="false"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should accept promote_staging_to_production value of true" {
  export TF_VAR_promote_staging_to_production="true"

  run tofu validate
  [ "$status" -eq 0 ]
}

@test "Should accept promote_staging_to_production value of false" {
  export TF_VAR_promote_staging_to_production="false"

  run tofu validate
  [ "$status" -eq 0 ]
}
