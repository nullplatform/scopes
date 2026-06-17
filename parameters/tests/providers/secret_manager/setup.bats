#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/secret_manager/setup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/secret_manager/setup"
  export DEPS="source $PARAMETERS_DIR/utils/log; source $PARAMETERS_DIR/utils/get_config_value"
}

teardown() {
  unset AWS_REGION AWS_DEFAULT_REGION SM_NAME_PREFIX SM_KMS_KEY_ID PROVIDER_CONFIG
}

@test "secret_manager setup: fails when AWS_REGION is missing" {
  unset AWS_REGION AWS_DEFAULT_REGION

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ AWS region not configured for secret_manager"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

@test "secret_manager setup: AWS_DEFAULT_REGION is honored when AWS_REGION is unset" {
  unset AWS_REGION
  export AWS_DEFAULT_REGION="eu-west-1"

  run bash -c "$DEPS; source $SCRIPT && echo REGION=\$AWS_REGION"

  assert_equal "$status" "0"
  assert_contains "$output" "REGION=eu-west-1"
}

@test "secret_manager setup: default name_prefix is 'parameters/'" {
  export AWS_REGION="us-east-1"

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$SM_NAME_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=parameters/"
}

@test "secret_manager setup: PROVIDER_CONFIG wins over env" {
  export AWS_REGION="us-east-1"
  export PROVIDER_CONFIG='{"region":"eu-central-1","name_prefix":"custom/","kms_key_id":"alias/mykey"}'

  run bash -c "$DEPS; source $SCRIPT && echo REGION=\$AWS_REGION PREFIX=\$SM_NAME_PREFIX KMS=\$SM_KMS_KEY_ID"

  assert_equal "$status" "0"
  assert_contains "$output" "REGION=eu-central-1"
  assert_contains "$output" "PREFIX=custom/"
  assert_contains "$output" "KMS=alias/mykey"
}

@test "secret_manager setup: kms_key_id is optional (empty when unset)" {
  export AWS_REGION="us-east-1"
  unset SM_KMS_KEY_ID

  run bash -c "$DEPS; source $SCRIPT && echo KMS=[\$SM_KMS_KEY_ID]"

  assert_equal "$status" "0"
  assert_contains "$output" "KMS=[]"
}
