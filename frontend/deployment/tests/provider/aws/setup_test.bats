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

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/provider/aws/setup"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export AWS_REGION="us-east-1"
  export TOFU_PROVIDER_BUCKET="my-terraform-state-bucket"
  export TOFU_LOCK_TABLE="terraform-locks"

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
run_aws_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Required environment variables
# =============================================================================
@test "Should fail when AWS_REGION is not set" {
  unset AWS_REGION

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ AWS_REGION is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • AWS_REGION"
}

@test "Should fail when TOFU_PROVIDER_BUCKET is not set" {
  unset TOFU_PROVIDER_BUCKET

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ TOFU_PROVIDER_BUCKET is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • TOFU_PROVIDER_BUCKET"
}

@test "Should fail when TOFU_LOCK_TABLE is not set" {
  unset TOFU_LOCK_TABLE

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ TOFU_LOCK_TABLE is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • TOFU_LOCK_TABLE"
}

@test "Should report all the variables that are not set" {
  unset AWS_REGION
  unset TOFU_PROVIDER_BUCKET
  unset TOFU_LOCK_TABLE

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ AWS_REGION is missing"
  assert_contains "$output" "   ❌ TOFU_PROVIDER_BUCKET is missing"
  assert_contains "$output" "   ❌ TOFU_LOCK_TABLE is missing"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    Set the missing variable(s) in the nullplatform agent Helm installation:"
  assert_contains "$output" "      • AWS_REGION"
  assert_contains "$output" "      • TOFU_PROVIDER_BUCKET"
  assert_contains "$output" "      • TOFU_LOCK_TABLE"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add aws_provider field to TOFU_VARIABLES" {
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

@test "Should add provider_resource_tags_json to TOFU_VARIABLES" {
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

# =============================================================================
# Test: TOFU_INIT_VARIABLES - backend configuration
# =============================================================================
@test "Should add S3 bucket configuration to TOFU_INIT_VARIABLES" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=bucket=my-terraform-state-bucket"
}

@test "Should add AWS region configuration to TOFU_INIT_VARIABLES" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=region=us-east-1"
}

@test "Should add Dynamo table configuration to TOFU_INIT_VARIABLES" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=dynamodb_table=terraform-locks"
}

@test "Should append to TOFU_INIT_VARIABLES when it previous settings are present" {
  export TOFU_INIT_VARIABLES="-var=existing=value"

  run_aws_setup

  assert_equal "$TOFU_INIT_VARIABLES" "-var=existing=value -backend-config=bucket=my-terraform-state-bucket -backend-config=region=us-east-1 -backend-config=dynamodb_table=terraform-locks"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  run_aws_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/provider/aws/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  export MODULES_TO_USE="existing/module"

  run_aws_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/provider/aws/modules"
}