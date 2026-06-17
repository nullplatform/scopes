#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/azure_key_vault/setup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/azure_key_vault/setup"
  export DEPS="source $PARAMETERS_DIR/utils/log; source $PARAMETERS_DIR/utils/get_config_value"
}

teardown() {
  unset AZURE_KEY_VAULT_NAME AZURE_KEY_VAULT_SECRET_PREFIX AZ_VAULT_NAME AZ_SECRET_PREFIX PROVIDER_CONFIG
}

@test "azure_key_vault setup: fails when vault name is missing" {
  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Azure Key Vault name not configured"
  assert_contains "$output" "🔧 How to fix:"
}

@test "azure_key_vault setup: succeeds with vault name from env" {
  export AZURE_KEY_VAULT_NAME="my-vault"

  run bash -c "$DEPS; source $SCRIPT && echo VAULT=\$AZ_VAULT_NAME PREFIX=\$AZ_SECRET_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "VAULT=my-vault"
  assert_contains "$output" "PREFIX=parameters-"
}

@test "azure_key_vault setup: PROVIDER_CONFIG wins over env" {
  export AZURE_KEY_VAULT_NAME="env-vault"
  export PROVIDER_CONFIG='{"vault_name":"cfg-vault","secret_prefix":"app-secret-"}'

  run bash -c "$DEPS; source $SCRIPT && echo VAULT=\$AZ_VAULT_NAME PREFIX=\$AZ_SECRET_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "VAULT=cfg-vault"
  assert_contains "$output" "PREFIX=app-secret-"
}

@test "azure_key_vault setup: rejects prefix with invalid characters" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_KEY_VAULT_SECRET_PREFIX="invalid_prefix/"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Invalid AZ_SECRET_PREFIX 'invalid_prefix/'"
  assert_contains "$output" "alphanumerics and dashes"
}

@test "azure_key_vault setup: accepts empty prefix" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_KEY_VAULT_SECRET_PREFIX=""

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=[\$AZ_SECRET_PREFIX]"

  assert_equal "$status" "0"
  # Empty env should fall through to default 'parameters-'
  assert_contains "$output" "PREFIX=[parameters-]"
}
