#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/hashicorp-vault/setup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/hashicorp-vault/setup"
  export DEPS="source $PARAMETERS_DIR/utils/log; source $PARAMETERS_DIR/utils/get_config_value"
}

teardown() {
  unset VAULT_ADDR VAULT_TOKEN VAULT_PATH_PREFIX PROVIDER_CONFIG
}

@test "vault setup: fails when VAULT_ADDR is missing" {
  unset VAULT_ADDR
  export VAULT_TOKEN="hvs.xxx"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault address not configured"
}

@test "vault setup: fails when VAULT_TOKEN is missing" {
  export VAULT_ADDR="https://vault.example.com"
  unset VAULT_TOKEN

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault token not configured"
}

@test "vault setup: path_prefix is hardcoded to secret/data/nullplatform" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_TOKEN="hvs.xxx"
  export PROVIDER_CONFIG='{"path_prefix":"kv/data/custom"}'

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=secret/data/nullplatform"
}

@test "vault setup: address from PROVIDER_CONFIG" {
  export VAULT_TOKEN="hvs.xxx"
  export PROVIDER_CONFIG='{"address":"https://cfg-vault.example.com"}'

  run bash -c "$DEPS; source $SCRIPT && echo ADDR=\$VAULT_ADDR"

  assert_equal "$status" "0"
  assert_contains "$output" "ADDR=https://cfg-vault.example.com"
}

@test "vault setup: token must come from env (not PROVIDER_CONFIG)" {
  export VAULT_ADDR="https://vault.example.com"
  unset VAULT_TOKEN
  export PROVIDER_CONFIG='{"token":"hvs.from-config"}'

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault token not configured"
}
