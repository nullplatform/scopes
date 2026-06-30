#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/azure-key-vault/setup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/azure-key-vault/setup"
  export DEPS="source $PARAMETERS_DIR/utils/log; source $PARAMETERS_DIR/utils/get_config_value"
}

teardown() {
  unset AZURE_KEY_VAULT_NAME AZ_VAULT_NAME AZ_SECRET_PREFIX PROVIDER_CONFIG
}

@test "azure-key-vault setup: fails when vault name is missing" {
  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Azure Key Vault name not configured"
  assert_contains "$output" "🔧 How to fix:"
}

@test "azure-key-vault setup: vault name from env" {
  export AZURE_KEY_VAULT_NAME="my-vault"

  run bash -c "$DEPS; source $SCRIPT && echo VAULT=\$AZ_VAULT_NAME PREFIX=\$AZ_SECRET_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "VAULT=my-vault"
  assert_contains "$output" "PREFIX=nullplatform-"
}

@test "azure-key-vault setup: secret_prefix is hardcoded to nullplatform-" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  # PROVIDER_CONFIG tries to override; ignored
  export PROVIDER_CONFIG='{"secret_prefix":"app-secret-"}'

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$AZ_SECRET_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=nullplatform-"
}

@test "azure-key-vault setup: vault_name from PROVIDER_CONFIG" {
  export PROVIDER_CONFIG='{"setup":{"vault_name":"cfg-vault"}}'

  run bash -c "$DEPS; source $SCRIPT && echo VAULT=\$AZ_VAULT_NAME"

  assert_equal "$status" "0"
  assert_contains "$output" "VAULT=cfg-vault"
}
