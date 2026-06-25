#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/hashicorp_vault/retrieve
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/hashicorp_vault/retrieve"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  cat > "$BATS_TEST_TMPDIR/bin/curl" << 'EOF'
#!/bin/bash
echo "ARGS: $@" >> "$CURL_LOG"
if [ "${MOCK_CURL_MODE:-success}" = "network_error" ]; then exit 6; fi
want_status=0
for arg in "$@"; do
  if [ "$arg" = "-w" ]; then want_status=1; break; fi
done
if [ -n "${MOCK_HTTP_BODY:-}" ]; then printf "%s" "$MOCK_HTTP_BODY"; fi
if [ "$want_status" = "1" ]; then printf "\n%s" "${MOCK_HTTP_STATUS:-200}"; fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export VAULT_ADDR="https://vault.example.com"
  export VAULT_TOKEN="hvs.test-token"
  export VAULT_PATH_PREFIX="secret/data/nullplatform"
  export EXTERNAL_ID="abc-123"

  export EXTERNAL_ID_PATH="$EXTERNAL_ID"
  export EXTERNAL_ID_VERSION=""
  export CONTEXT='{}'
  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "vault retrieve: 200 returns stored value" {
  body='{"data":{"data":{"value":"the-real-secret","parameter_id":42}}}'

  run bash -c "$DEPS; MOCK_HTTP_STATUS=200 MOCK_HTTP_BODY='$body' source $SCRIPT"

  assert_equal "$status" "0"
  value=$(echo "$output" | jq -r '.value')
  assert_equal "$value" "the-real-secret"
}

@test "vault retrieve: 404 fails with troubleshooting" {
  run bash -c "$DEPS; MOCK_HTTP_STATUS=404 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "not found in Vault"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

@test "vault retrieve: 403 fails with auth troubleshooting" {
  run bash -c "$DEPS; MOCK_HTTP_STATUS=403 MOCK_HTTP_BODY='{\"errors\":[\"permission denied\"]}' source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault GET failed with HTTP 403"
  assert_contains "$output" "lacks read permission"
}

@test "vault retrieve: 500 fails with server troubleshooting" {
  run bash -c "$DEPS; MOCK_HTTP_STATUS=500 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault GET failed with HTTP 500"
}

@test "vault retrieve: network error fails with connectivity troubleshooting" {
  run bash -c "$DEPS; MOCK_CURL_MODE=network_error source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Network error calling Vault"
}

@test "vault retrieve: GETs the correct Vault URL with token header" {
  body='{"data":{"data":{"value":"x"}}}'
  run bash -c "$DEPS; MOCK_HTTP_STATUS=200 MOCK_HTTP_BODY='$body' source $SCRIPT"

  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "-H X-Vault-Token: hvs.test-token"
  assert_contains "$captured" "https://vault.example.com/v1/secret/data/nullplatform/abc-123"
}

@test "vault retrieve: honors custom VAULT_PATH_PREFIX" {
  export VAULT_PATH_PREFIX="kv/data/custom-mount"
  body='{"data":{"data":{"value":"x"}}}'

  run bash -c "$DEPS; MOCK_HTTP_STATUS=200 MOCK_HTTP_BODY='$body' source $SCRIPT"

  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "https://vault.example.com/v1/kv/data/custom-mount/abc-123"
}
