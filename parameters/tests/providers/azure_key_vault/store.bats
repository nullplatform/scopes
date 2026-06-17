#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/azure_key_vault/store
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/azure_key_vault/store"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/uuidgen" << 'EOF'
#!/bin/bash
echo "fixed-akv-uuid"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/uuidgen"

  export AZ_LOG="$BATS_TEST_TMPDIR/az.log"
  cat > "$BATS_TEST_TMPDIR/bin/az" << EOF
#!/bin/bash
echo "ARGS: \$@" >> "$AZ_LOG"
if [ "\${MOCK_AZ_EXIT:-0}" -ne 0 ]; then exit \$MOCK_AZ_EXIT; fi
echo "https://my-vault.vault.azure.net/secrets/parameters-fixed-akv-uuid/abc123def456"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/az"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export AZ_VAULT_NAME="my-vault"
  export AZ_SECRET_PREFIX="parameters-"
  export PARAMETER_VALUE="my-secret-value"

  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "azure_key_vault store: outputs external_id and metadata" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  secret_name=$(echo "$output" | jq -r '.metadata.secret_name')
  azure_secret_id=$(echo "$output" | jq -r '.metadata.azure_secret_id')
  vault_name=$(echo "$output" | jq -r '.metadata.vault_name')
  assert_equal "$external_id" "fixed-akv-uuid"
  assert_equal "$secret_name" "parameters-fixed-akv-uuid"
  assert_contains "$azure_secret_id" "vault.azure.net/secrets/parameters-fixed-akv-uuid"
  assert_equal "$vault_name" "my-vault"
}

@test "azure_key_vault store: calls az keyvault secret set" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "keyvault secret set"
  assert_contains "$captured" "--vault-name my-vault"
  assert_contains "$captured" "--name parameters-fixed-akv-uuid"
  assert_contains "$captured" "--value my-secret-value"
}

@test "azure_key_vault store: honors custom AZ_SECRET_PREFIX" {
  export AZ_SECRET_PREFIX="app-prod-"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "--name app-prod-fixed-akv-uuid"
}

@test "azure_key_vault store: fails with troubleshooting on az error" {
  run bash -c "$DEPS; MOCK_AZ_EXIT=1 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store secret in Azure Key Vault 'my-vault'"
  assert_contains "$output" "💡 Possible causes:"
}
