#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/hashicorp_vault/store
# external_id is now composed via parameters/utils/build_external_id.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_ROOT="$PARAMETERS_DIR"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/hashicorp_vault/store"

  mkdir -p "$BATS_TEST_TMPDIR/bin"

  # Mock np CLI: handles `<entity> read --id <id> --format json --query .slug`
  cat > "$BATS_TEST_TMPDIR/bin/np" << 'EOF'
#!/bin/bash
# Args: <entity_type> read --id <id> --format json --query .slug
entity_type="$1"
case "$entity_type" in
  organization) echo "\"acme\"" ;;
  account)      echo "\"prod\"" ;;
  namespace)    echo "\"billing\"" ;;
  application)  echo "\"api\"" ;;
  scope)        echo "\"main\"" ;;
  *)            echo "\"unknown\"" ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/np"

  # Mock curl
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  cat > "$BATS_TEST_TMPDIR/bin/curl" << EOF
#!/bin/bash
echo "ARGS: \$@" >> "$CURL_LOG"
exit \${MOCK_CURL_EXIT:-0}
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export VAULT_ADDR="https://vault.example.com"
  export VAULT_TOKEN="hvs.test-token"
  export VAULT_PATH_PREFIX="secret/data/parameters"
  export PARAMETER_ID=42
  export PARAMETER_VALUE="my-secret"
  export CONTEXT='{
    "parameter_id": 42,
    "value": "my-secret",
    "entities": {
      "organization": "1255165411",
      "account": "95118862",
      "namespace": "37094320",
      "application": "321402625"
    },
    "dimensions": {}
  }'

  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "vault store: external_id composed from entities + parameter_id" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  expected="organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/42"
  assert_equal "$external_id" "$expected"
}

@test "vault store: external_id includes sorted dimensions" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.dimensions = {environment: "prod", country: "arg"}')

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  # Dimensions sorted alphabetically: country before environment
  assert_contains "$external_id" "country=arg/environment=prod/42"
}

@test "vault store: vault_path contains external_id" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  vault_path=$(echo "$output" | jq -r '.metadata.vault_path')
  assert_contains "$vault_path" "secret/data/parameters/organization=acme-1255165411"
  assert_contains "$vault_path" "/42"
}

@test "vault store: POSTs to Vault URL with token" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "-X POST"
  assert_contains "$captured" "-H X-Vault-Token: hvs.test-token"
  assert_contains "$captured" "https://vault.example.com/v1/secret/data/parameters/organization=acme-1255165411"
}

@test "vault store: POST body contains parameter_id, value, external_id, stored_at" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" '"parameter_id":42'
  assert_contains "$captured" '"value":"my-secret"'
  assert_contains "$captured" '"external_id":"organization=acme-1255165411'
  assert_contains "$captured" '"stored_at":"'
}

@test "vault store: fails with troubleshooting when curl returns non-zero" {
  run bash -c "$DEPS; MOCK_CURL_EXIT=22 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store parameter in Vault"
  assert_contains "$output" "💡 Possible causes:"
}

@test "vault store: works without dimensions" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.dimensions)')

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  expected="organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/42"
  assert_equal "$external_id" "$expected"
}
