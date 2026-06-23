#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/azure_key_vault/retrieve
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/azure_key_vault/retrieve"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export AZ_LOG="$BATS_TEST_TMPDIR/az.log"
  cat > "$BATS_TEST_TMPDIR/bin/az" << 'EOF'
#!/bin/bash
echo "ARGS: $@" >> "$AZ_LOG"
case "${MOCK_AZ_MODE:-success}" in
  success)
    echo "the-stored-value"
    ;;
  not_found)
    echo "(SecretNotFound) A secret with (name/id) X was not found in this key vault." >&2
    exit 3
    ;;
  auth_error)
    echo "(Forbidden) The user is not authorized to perform this action." >&2
    exit 1
    ;;
  *)
    echo "(InternalServerError) something went wrong." >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/az"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export AZ_VAULT_NAME="my-vault"
  export AZ_SECRET_PREFIX="parameters-"
  export EXTERNAL_ID="abc-123"

  export EXTERNAL_ID_PATH="$EXTERNAL_ID"
  export EXTERNAL_ID_VERSION=""
  export CONTEXT='{}'
  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "azure_key_vault retrieve: success → returns value" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  value=$(echo "$output" | jq -r '.value')
  assert_equal "$value" "the-stored-value"
}

@test "azure_key_vault retrieve: SecretNotFound → 'value not found'" {
  run bash -c "$DEPS; MOCK_AZ_MODE=not_found source $SCRIPT"

  assert_equal "$status" "0"
  value=$(echo "$output" | jq -r '.value')
  assert_equal "$value" "value not found"
}

@test "azure_key_vault retrieve: auth_error fails with troubleshooting" {
  run bash -c "$DEPS; MOCK_AZ_MODE=auth_error source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to retrieve secret"
  assert_contains "$output" "lacks 'Get' permission"
}

@test "azure_key_vault retrieve: unknown errors fail loud" {
  run bash -c "$DEPS; MOCK_AZ_MODE=other source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to retrieve secret"
}

@test "azure_key_vault retrieve: calls az keyvault secret show" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "keyvault secret show"
  assert_contains "$captured" "--vault-name my-vault"
  assert_contains "$captured" "--name parameters-abc-123"
  assert_contains "$captured" "--query value"
}
