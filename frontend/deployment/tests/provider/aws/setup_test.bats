#!/usr/bin/env bats
# =============================================================================
# Unit tests for provider/aws/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/provider/aws/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/provider/aws/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"

  # Load shared test utilities
  source "$PROJECT_DIR/tests/test_utils.bash"

  # Initialize required environment variables
  export AWS_REGION="us-east-1"
  export TOFU_PROVIDER_BUCKET="my-terraform-state-bucket"
  export TOFU_LOCK_TABLE="terraform-locks"

  # Initialize TOFU_VARIABLES with existing keys to verify script merges (not replaces)
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
run_aws_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Required environment variables
# =============================================================================
@test "fails when AWS_REGION is not set" {
  unset AWS_REGION

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "AWS_REGION is not set"
}

@test "fails when TOFU_PROVIDER_BUCKET is not set" {
  unset TOFU_PROVIDER_BUCKET

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "TOFU_PROVIDER_BUCKET is not set"
}

@test "fails when TOFU_LOCK_TABLE is not set" {
  unset TOFU_LOCK_TABLE

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "TOFU_LOCK_TABLE is not set"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "TOFU_VARIABLES matches expected structure on success" {
  run_aws_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "aws_provider": {
    "region": "us-east-1",
    "state_bucket": "my-terraform-state-bucket",
    "lock_table": "terraform-locks"
  },
  "provider_resource_tags_json": {}
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "TOFU_VARIABLES includes custom resource tags" {
  export RESOURCE_TAGS_JSON='{"Environment": "production", "Team": "platform"}'

  run_aws_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "aws_provider": {
    "region": "us-east-1",
    "state_bucket": "my-terraform-state-bucket",
    "lock_table": "terraform-locks"
  },
  "provider_resource_tags_json": {"Environment": "production", "Team": "platform"}
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "TOFU_VARIABLES uses different region" {
  export AWS_REGION="eu-west-1"

  run_aws_setup

  local region=$(echo "$TOFU_VARIABLES" | jq -r '.aws_provider.region')
  assert_equal "$region" "eu-west-1"
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES - backend configuration
# =============================================================================
@test "TOFU_INIT_VARIABLES includes bucket backend config" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=bucket=my-terraform-state-bucket"
}

@test "TOFU_INIT_VARIABLES includes region backend config" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=region=us-east-1"
}

@test "TOFU_INIT_VARIABLES includes dynamodb_table backend config" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=dynamodb_table=terraform-locks"
}

@test "TOFU_INIT_VARIABLES appends to existing variables" {
  export TOFU_INIT_VARIABLES="-var=existing=value"

  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-var=existing=value"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=bucket=my-terraform-state-bucket"
}

# =============================================================================
# Test: LocalStack/AWS_ENDPOINT_URL configuration
# =============================================================================
@test "adds LocalStack backend config when AWS_ENDPOINT_URL is set" {
  export AWS_ENDPOINT_URL="http://localhost:4566"

  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=force_path_style=true"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=skip_credentials_validation=true"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=skip_metadata_api_check=true"
  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=skip_region_validation=true"
}

@test "includes endpoint config with LocalStack URL" {
  export AWS_ENDPOINT_URL="http://localhost:4566"

  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" '-backend-config=endpoints={s3="http://localhost:4566",dynamodb="http://localhost:4566"}'
}

@test "does not add LocalStack config when AWS_ENDPOINT_URL is not set" {
  unset AWS_ENDPOINT_URL

  run_aws_setup

  # Should not contain LocalStack-specific configs
  if [[ "$TOFU_INIT_VARIABLES" == *"force_path_style"* ]]; then
    echo "TOFU_INIT_VARIABLES should not contain force_path_style when AWS_ENDPOINT_URL is not set"
    echo "Actual: $TOFU_INIT_VARIABLES"
    return 1
  fi
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "adds module to MODULES_TO_USE when empty" {
  run_aws_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/provider/aws/modules"
}

@test "appends module to existing MODULES_TO_USE" {
  export MODULES_TO_USE="existing/module"

  run_aws_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/provider/aws/modules"
}

@test "preserves multiple existing modules in MODULES_TO_USE" {
  export MODULES_TO_USE="first/module,second/module"

  run_aws_setup

  assert_equal "$MODULES_TO_USE" "first/module,second/module,$PROJECT_DIR/provider/aws/modules"
}

# =============================================================================
# Test: Default values
# =============================================================================
@test "uses empty object for RESOURCE_TAGS_JSON when not set" {
  unset RESOURCE_TAGS_JSON

  run_aws_setup

  local tags=$(echo "$TOFU_VARIABLES" | jq -r '.provider_resource_tags_json')
  assert_equal "$tags" "{}"
}
