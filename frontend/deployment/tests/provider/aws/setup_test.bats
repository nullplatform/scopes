#!/usr/bin/env bats
# =============================================================================
# Unit tests for provider/aws/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/aws/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/provider/aws/setup"

  # Load shared test utilities
  source "$PROJECT_DIR/tests/test_utils.bash"

  # Initialize variables that the script expects to exist
  export TOFU_VARIABLES='{}'
  export TOFU_INIT_VARIABLES=""
  export MODULES_TO_USE=""

  # Set required AWS variables
  export AWS_REGION="us-east-1"
  export TOFU_PROVIDER_BUCKET="my-state-bucket"
  export TOFU_LOCK_TABLE="my-lock-table"
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
# Test: TOFU_VARIABLES - aws_provider object
# =============================================================================
@test "adds aws_provider to TOFU_VARIABLES" {
  run_aws_setup

  local aws_provider=$(echo "$TOFU_VARIABLES" | jq '.aws_provider')
  assert_not_empty "$aws_provider" "aws_provider"
}

@test "aws_provider contains correct region" {
  run_aws_setup

  local region=$(echo "$TOFU_VARIABLES" | jq -r '.aws_provider.region')
  assert_equal "$region" "us-east-1"
}

@test "aws_provider contains correct state_bucket" {
  run_aws_setup

  local bucket=$(echo "$TOFU_VARIABLES" | jq -r '.aws_provider.state_bucket')
  assert_equal "$bucket" "my-state-bucket"
}

@test "aws_provider contains correct lock_table" {
  run_aws_setup

  local table=$(echo "$TOFU_VARIABLES" | jq -r '.aws_provider.lock_table')
  assert_equal "$table" "my-lock-table"
}

@test "TOFU_VARIABLES aws_provider matches expected structure" {
  run_aws_setup

  local expected='{
  "region": "us-east-1",
  "state_bucket": "my-state-bucket",
  "lock_table": "my-lock-table"
}'

  local actual=$(echo "$TOFU_VARIABLES" | jq -S '.aws_provider')
  local expected_sorted=$(echo "$expected" | jq -S .)

  if [ "$actual" != "$expected_sorted" ]; then
    echo "aws_provider does not match expected structure"
    echo ""
    echo "Expected:"
    echo "$expected_sorted"
    echo ""
    echo "Actual:"
    echo "$actual"
    return 1
  fi
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES - backend config
# =============================================================================
@test "TOFU_INIT_VARIABLES contains bucket backend-config" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" '-backend-config="bucket=my-state-bucket"'
}

@test "TOFU_INIT_VARIABLES contains region backend-config" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" '-backend-config="region=us-east-1"'
}

@test "TOFU_INIT_VARIABLES contains dynamodb_table backend-config" {
  run_aws_setup

  assert_contains "$TOFU_INIT_VARIABLES" '-backend-config="dynamodb_table=my-lock-table"'
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "MODULES_TO_USE contains aws modules path" {
  run_aws_setup

  assert_contains "$MODULES_TO_USE" "provider/aws/modules"
}

@test "MODULES_TO_USE appends to existing modules" {
  export MODULES_TO_USE="existing/module"
  run_aws_setup

  assert_contains "$MODULES_TO_USE" "existing/module"
  assert_contains "$MODULES_TO_USE" "provider/aws/modules"
}

@test "MODULES_TO_USE uses comma separator when appending" {
  export MODULES_TO_USE="existing/module"
  run_aws_setup

  assert_contains "$MODULES_TO_USE" "existing/module,"
}
