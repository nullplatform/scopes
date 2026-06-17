#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/hashicorp_vault/store
# Verifies HTTP request shape AND JSON output remain byte-compatible with
# the previous parameters/vault/store implementation.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/hashicorp_vault/store"

  # Mock uuidgen for deterministic external_id
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/uuidgen" << 'EOF'
#!/bin/bash
echo "fixed-test-uuid"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/uuidgen"

  # Mock curl: capture args to file, return success by default
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  cat > "$BATS_TEST_TMPDIR/bin/curl" << EOF
#!/bin/bash
echo "ARGS: \$@" >> "$CURL_LOG"
exit \${MOCK_CURL_EXIT:-0}
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  # Defaults from setup() — operation script assumes these are present
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_TOKEN="hvs.test-token"
  export VAULT_PATH_PREFIX="secret/data/parameters"
  export PARAMETER_ID=42
  export PARAMETER_VALUE="my-super-secret"

  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "vault store: outputs JSON with external_id and vault_path metadata" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  # Parse with jq to be robust against whitespace
  external_id=$(echo "$output" | jq -r '.external_id')
  vault_path=$(echo "$output" | jq -r '.metadata.vault_path')
  assert_equal "$external_id" "fixed-test-uuid"
  assert_equal "$vault_path" "secret/data/parameters/fixed-test-uuid"
}

@test "vault store: POSTs to correct Vault URL with token header" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "-X POST"
  assert_contains "$captured" "-H X-Vault-Token: hvs.test-token"
  assert_contains "$captured" "https://vault.example.com/v1/secret/data/parameters/fixed-test-uuid"
}

@test "vault store: POST body contains parameter_id, value, external_id, stored_at" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" '"parameter_id":42'
  assert_contains "$captured" '"value":"my-super-secret"'
  assert_contains "$captured" '"external_id":"fixed-test-uuid"'
  assert_contains "$captured" '"stored_at":"'
}

@test "vault store: fails with troubleshooting when curl returns non-zero" {
  export MOCK_CURL_EXIT=22

  run bash -c "$DEPS; MOCK_CURL_EXIT=22 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store parameter in Vault at https://vault.example.com"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

@test "vault store: honors custom VAULT_PATH_PREFIX" {
  export VAULT_PATH_PREFIX="kv/data/custom-mount"

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  vault_path=$(echo "$output" | jq -r '.metadata.vault_path')
  assert_equal "$vault_path" "kv/data/custom-mount/fixed-test-uuid"

  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "https://vault.example.com/v1/kv/data/custom-mount/fixed-test-uuid"
}

@test "vault store: jq-escapes the value so quotes inside don't break the body" {
  export PARAMETER_VALUE='val"with"quotes'

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  # jq -R turns the literal value into "val\"with\"quotes" — escaped
  assert_contains "$captured" 'val\"with\"quotes'
}
