#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/hashicorp_vault/setup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/hashicorp_vault/setup"
  export DEPS="source $PARAMETERS_DIR/utils/log; source $PARAMETERS_DIR/utils/get_config_value"
}

teardown() {
  unset VAULT_ADDR VAULT_TOKEN VAULT_PATH_PREFIX PROVIDER_CONFIG
}

@test "vault setup: fails with troubleshooting when VAULT_ADDR is missing" {
  unset VAULT_ADDR
  export VAULT_TOKEN="hvs.xxx"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault address not configured"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

@test "vault setup: fails with troubleshooting when VAULT_TOKEN is missing" {
  export VAULT_ADDR="https://vault.example.com"
  unset VAULT_TOKEN

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault token not configured"
}

@test "vault setup: succeeds with both env vars set, exports them" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_TOKEN="hvs.xxx"

  run bash -c "$DEPS; source $SCRIPT && echo ADDR=\$VAULT_ADDR TOKEN=\$VAULT_TOKEN PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "ADDR=https://vault.example.com"
  assert_contains "$output" "TOKEN=hvs.xxx"
  assert_contains "$output" "PREFIX=secret/data/parameters"
}

@test "vault setup: PROVIDER_CONFIG wins over env var" {
  export VAULT_ADDR="https://env-vault.com"
  export VAULT_TOKEN="env-token"
  export PROVIDER_CONFIG='{"address":"https://provider-vault.com","token":"provider-token"}'

  run bash -c "$DEPS; source $SCRIPT && echo ADDR=\$VAULT_ADDR TOKEN=\$VAULT_TOKEN"

  assert_equal "$status" "0"
  assert_contains "$output" "ADDR=https://provider-vault.com"
  assert_contains "$output" "TOKEN=provider-token"
}

@test "vault setup: custom path_prefix from PROVIDER_CONFIG" {
  export PROVIDER_CONFIG='{"address":"https://v.com","token":"t","path_prefix":"kv/data/custom"}'

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=kv/data/custom"
}

@test "vault setup: reads VAULT_PATH_PREFIX from env if PROVIDER_CONFIG has no path_prefix" {
  export VAULT_ADDR="https://v.com"
  export VAULT_TOKEN="t"
  export VAULT_PATH_PREFIX="kv/data/from-env"

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=kv/data/from-env"
}
