#!/usr/bin/env bats
# =============================================================================
# Unit tests for build_context script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/scripts/build_context_test.bats
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

  CONTEXT=$(cat "$PROJECT_DIR/tests/resources/context.json")
  # SERVICE_PATH should point to azure-apps root (parent of deployment)
  SERVICE_PATH="$(cd "$PROJECT_DIR/.." && pwd)"
  TEST_OUTPUT_DIR=$(mktemp -d)

  export CONTEXT SERVICE_PATH TEST_OUTPUT_DIR
}

# Teardown - runs after each test
teardown() {
  # Clean up temp directory
  if [ -d "$TEST_OUTPUT_DIR" ]; then
    rm -rf "$TEST_OUTPUT_DIR"
  fi
}

# =============================================================================
# Helper functions
# =============================================================================
run_build_context() {
  # Source the build_context script
  source "$PROJECT_DIR/scripts/build_context"
}

# =============================================================================
# Test: Basic extraction from CONTEXT
# =============================================================================
@test "Should extract SCOPE_ID from context" {
  run_build_context

  assert_equal "$SCOPE_ID" "7"
}

@test "Should extract DEPLOYMENT_ID from context" {
  run_build_context

  assert_equal "$DEPLOYMENT_ID" "8"
}

@test "Should extract DOCKER_IMAGE from context" {
  run_build_context

  assert_equal "$DOCKER_IMAGE" "myregistry.azurecr.io/tools/automation:v1.0.0"
}

# =============================================================================
# Test: NRN component extraction
# =============================================================================
@test "Should extract ORGANIZATION_ID from NRN" {
  run_build_context

  assert_equal "$ORGANIZATION_ID" "1"
}

@test "Should extract ACCOUNT_ID from NRN" {
  run_build_context

  assert_equal "$ACCOUNT_ID" "2"
}

@test "Should extract NAMESPACE_ID from NRN" {
  run_build_context

  assert_equal "$NAMESPACE_ID" "3"
}

@test "Should extract APPLICATION_ID from NRN" {
  run_build_context

  assert_equal "$APPLICATION_ID" "4"
}

# =============================================================================
# Test: APP_NAME generation
# =============================================================================
@test "Should generate APP_NAME from slugs and scope_id" {
  run_build_context

  # Format: {namespace}-{application}-{scope}-{scope_id}
  assert_equal "$APP_NAME" "tools-automation-development-tools-7"
}

@test "Should generate APP_NAME within Azure max length (60 chars)" {
  run_build_context

  local name_length=${#APP_NAME}
  assert_less_than "$name_length" "61" "APP_NAME length"
}

# =============================================================================
# Test: TOFU_VARIABLES - Full JSON validation
# =============================================================================
@test "Should generate TOFU_VARIABLES with all expected values from context" {
  run_build_context

  # Build expected JSON - validates all values extracted from capabilities
  local expected_json
  expected_json=$(cat <<'EOF'
{
  "app_name": "tools-automation-development-tools-7",
  "swap_slots": false,
  "docker_image": "myregistry.azurecr.io/tools/automation:v1.0.0",
  "docker_registry_url": "https://index.docker.io",
  "docker_registry_username": "",
  "docker_registry_password": "",
  "sku_name": "P1v3",
  "websockets_enabled": false,
  "health_check_path": "/healthz",
  "health_check_eviction_time_in_min": 5,
  "enable_staging_slot": false,
  "enable_autoscaling": true,
  "fixed_instances": 2,
  "autoscale_min_instances": 2,
  "autoscale_max_instances": 5,
  "cpu_scale_out_threshold": 75,
  "memory_scale_out_threshold": 80,
  "parameter_json": "{\"DATABASE_URL\":\"postgres://localhost:5432/db\",\"LOG_LEVEL\":\"info\"}",
  "https_only": true,
  "minimum_tls_version": "1.2",
  "ftps_state": "Disabled",
  "client_affinity_enabled": false,
  "enable_logging": true,
  "application_logs_level": "Information",
  "http_logs_retention_days": 7
}
EOF
)

  assert_json_equal "$TOFU_VARIABLES" "$expected_json" "TOFU_VARIABLES"
}

# =============================================================================
# Test: TOFU_VARIABLES - Special logic (conditional values)
# =============================================================================
@test "Should disable autoscaling when scaling_type is fixed" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.scaling_type = "fixed"')

  run_build_context

  local enable_autoscaling
  enable_autoscaling=$(echo "$TOFU_VARIABLES" | jq -r '.enable_autoscaling')
  assert_equal "$enable_autoscaling" "false"
}

# =============================================================================
# Test: TOFU_VARIABLES - Default values
# =============================================================================
@test "Should use default health_check_eviction_time 1 when not specified" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.scope.capabilities.health_check.eviction_time_in_min)')

  run_build_context

  local eviction_time
  eviction_time=$(echo "$TOFU_VARIABLES" | jq -r '.health_check_eviction_time_in_min')
  assert_equal "$eviction_time" "1"
}

# =============================================================================
# Test: TOFU_VARIABLES - Environment variable overrides
# =============================================================================
@test "Should use ENABLE_STAGING_SLOT from environment when set" {
  export ENABLE_STAGING_SLOT="true"

  run_build_context

  local staging_slot
  staging_slot=$(echo "$TOFU_VARIABLES" | jq -r '.enable_staging_slot')
  assert_equal "$staging_slot" "true"
}

@test "Should use provided DOCKER_REGISTRY_URL when set" {
  export DOCKER_REGISTRY_URL="myregistry.azurecr.io"

  run_build_context

  local registry_url
  registry_url=$(echo "$TOFU_VARIABLES" | jq -r '.docker_registry_url')
  assert_equal "$registry_url" "myregistry.azurecr.io"
}

@test "Should use provided SWAP_SLOTS value" {
  export SWAP_SLOTS="true"

  run_build_context

  local swap_slots
  swap_slots=$(echo "$TOFU_VARIABLES" | jq -r '.swap_slots')
  assert_equal "$swap_slots" "true"
}

# =============================================================================
# Test: OUTPUT_DIR and TF_WORKING_DIR
# =============================================================================
@test "Should create OUTPUT_DIR with scope_id" {
  run_build_context

  assert_equal "$OUTPUT_DIR" "$SERVICE_PATH/output/7"
}

@test "Should create TF_WORKING_DIR as OUTPUT_DIR/terraform" {
  run_build_context

  assert_contains "$TF_WORKING_DIR" "$OUTPUT_DIR/terraform"
}

@test "Should create OUTPUT_DIR directory" {
  run_build_context

  assert_directory_exists "$OUTPUT_DIR"
}

@test "Should create TF_WORKING_DIR directory" {
  run_build_context

  assert_directory_exists "$TF_WORKING_DIR"
}

@test "Should use NP_OUTPUT_DIR when set" {
  export NP_OUTPUT_DIR="$TEST_OUTPUT_DIR"

  run_build_context

  assert_equal "$OUTPUT_DIR" "$TEST_OUTPUT_DIR/output/7"
}

# =============================================================================
# Test: Exports are set
# =============================================================================
@test "Should export SCOPE_ID" {
  run_build_context

  assert_not_empty "$SCOPE_ID" "SCOPE_ID"
}

@test "Should export DEPLOYMENT_ID" {
  run_build_context

  assert_not_empty "$DEPLOYMENT_ID" "DEPLOYMENT_ID"
}

@test "Should export APP_NAME" {
  run_build_context

  assert_not_empty "$APP_NAME" "APP_NAME"
}

@test "Should export DOCKER_IMAGE" {
  run_build_context

  assert_not_empty "$DOCKER_IMAGE" "DOCKER_IMAGE"
}

@test "Should export OUTPUT_DIR" {
  run_build_context

  assert_not_empty "$OUTPUT_DIR" "OUTPUT_DIR"
}

@test "Should export TF_WORKING_DIR" {
  run_build_context

  assert_not_empty "$TF_WORKING_DIR" "TF_WORKING_DIR"
}

@test "Should export TOFU_VARIABLES" {
  run_build_context

  assert_not_empty "$TOFU_VARIABLES" "TOFU_VARIABLES"
}

@test "Should export CONTEXT" {
  run_build_context

  assert_not_empty "$CONTEXT" "CONTEXT"
}
