#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/azure-key-vault/delete
# Two-step: soft-delete + purge. Purge failures are warnings, not errors.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/azure-key-vault/delete"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export AZ_LOG="$BATS_TEST_TMPDIR/az.log"
  # The mock checks args to determine if this is `delete` or `purge`, and
  # picks MOCK_DELETE_MODE / MOCK_PURGE_MODE accordingly.
  cat > "$BATS_TEST_TMPDIR/bin/az" << 'EOF'
#!/bin/bash
echo "ARGS: $@" >> "$AZ_LOG"

# Identify which sub-command was called
sub_action=""
for arg in "$@"; do
  case "$arg" in
    delete) sub_action="delete" ;;
    purge)  sub_action="purge" ;;
  esac
done

if [ "$sub_action" = "delete" ]; then mode="${MOCK_DELETE_MODE:-success}"
elif [ "$sub_action" = "purge" ]; then mode="${MOCK_PURGE_MODE:-success}"
else mode="success"; fi

case "$mode" in
  success) ;;
  not_found)
    echo "(SecretNotFound) A secret with (name/id) X was not found in this key vault." >&2
    exit 3
    ;;
  auth_error)
    echo "(Forbidden) The user is not authorized to perform this action." >&2
    exit 1
    ;;
  purge_forbidden)
    echo "(Forbidden) Purge permission missing." >&2
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
  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "azure-key-vault delete: both delete + purge succeed → {success: true}" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  success=$(echo "$output" | jq -r '.success')
  assert_equal "$success" "true"
}

@test "azure-key-vault delete: SecretNotFound on delete is idempotent → success" {
  run bash -c "$DEPS; MOCK_DELETE_MODE=not_found source $SCRIPT"

  assert_equal "$status" "0"
  success=$(echo "$output" | jq -r '.success')
  assert_equal "$success" "true"
}

@test "azure-key-vault delete: delete auth_error fails with troubleshooting" {
  run bash -c "$DEPS; MOCK_DELETE_MODE=auth_error source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to delete secret"
  assert_contains "$output" "lacks 'Delete' permission"
}

@test "azure-key-vault delete: purge forbidden is downgraded to warning, still returns success" {
  run --separate-stderr bash -c "$DEPS; MOCK_PURGE_MODE=purge_forbidden source $SCRIPT"

  assert_equal "$status" "0"
  success=$(echo "$output" | jq -r '.success')
  assert_equal "$success" "true"
  assert_contains "$stderr" "⚠️"
  assert_contains "$stderr" "Purge permission missing"
}

@test "azure-key-vault delete: purge other failure is warning, still success" {
  run --separate-stderr bash -c "$DEPS; MOCK_PURGE_MODE=other source $SCRIPT"

  assert_equal "$status" "0"
  success=$(echo "$output" | jq -r '.success')
  assert_equal "$success" "true"
  assert_contains "$stderr" "⚠️ Purge failed"
}

@test "azure-key-vault delete: calls both delete and purge sub-commands" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "keyvault secret delete"
  assert_contains "$captured" "keyvault secret purge"
  assert_contains "$captured" "--name parameters-abc-123"
}

@test "azure-key-vault delete: skips purge if delete returned not_found" {
  run bash -c "$DEPS; MOCK_DELETE_MODE=not_found source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "keyvault secret delete"
  # Purge should NOT have been called since delete already said "not found"
  [[ "$captured" != *"keyvault secret purge"* ]]
}
