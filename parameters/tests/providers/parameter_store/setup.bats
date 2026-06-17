#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/parameter_store/setup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/parameter_store/setup"
  export DEPS="source $PARAMETERS_DIR/utils/log; source $PARAMETERS_DIR/utils/get_config_value"
}

teardown() {
  unset AWS_REGION AWS_DEFAULT_REGION PS_NAME_PREFIX PS_KMS_KEY_ID PS_TIER PROVIDER_CONFIG
}

@test "parameter_store setup: fails when AWS_REGION is missing" {
  unset AWS_REGION AWS_DEFAULT_REGION

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ AWS region not configured for parameter_store"
}

@test "parameter_store setup: default name_prefix has leading and trailing slash" {
  export AWS_REGION="us-east-1"

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$PS_NAME_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=/nullplatform/parameters/"
}

@test "parameter_store setup: normalizes prefix without leading slash" {
  export AWS_REGION="us-east-1"
  export PS_NAME_PREFIX="custom/path/"

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$PS_NAME_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=/custom/path/"
}

@test "parameter_store setup: normalizes prefix without trailing slash" {
  export AWS_REGION="us-east-1"
  export PS_NAME_PREFIX="/custom/path"

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$PS_NAME_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=/custom/path/"
}

@test "parameter_store setup: default tier is Standard" {
  export AWS_REGION="us-east-1"

  run bash -c "$DEPS; source $SCRIPT && echo TIER=\$PS_TIER"

  assert_equal "$status" "0"
  assert_contains "$output" "TIER=Standard"
}

@test "parameter_store setup: accepts Advanced tier" {
  export AWS_REGION="us-east-1"
  export PS_TIER="Advanced"

  run bash -c "$DEPS; source $SCRIPT && echo TIER=\$PS_TIER"

  assert_equal "$status" "0"
  assert_contains "$output" "TIER=Advanced"
}

@test "parameter_store setup: rejects invalid tier with troubleshooting" {
  export AWS_REGION="us-east-1"
  export PS_TIER="Bogus"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Invalid PS_TIER 'Bogus'"
  assert_contains "$output" "Standard, Advanced, Intelligent-Tiering"
}

@test "parameter_store setup: PROVIDER_CONFIG wins over env" {
  export AWS_REGION="us-east-1"
  export PROVIDER_CONFIG='{"region":"eu-west-1","name_prefix":"/cfg/path/","kms_key_id":"alias/cfg","tier":"Advanced"}'

  run bash -c "$DEPS; source $SCRIPT && echo REGION=\$AWS_REGION PREFIX=\$PS_NAME_PREFIX KMS=\$PS_KMS_KEY_ID TIER=\$PS_TIER"

  assert_equal "$status" "0"
  assert_contains "$output" "REGION=eu-west-1"
  assert_contains "$output" "PREFIX=/cfg/path/"
  assert_contains "$output" "KMS=alias/cfg"
  assert_contains "$output" "TIER=Advanced"
}
