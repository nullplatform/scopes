#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/azure-key-vault/store
# AKV transforms / and = to - in the secret name (canonical form has slashes).
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_ROOT="$PARAMETERS_DIR"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/azure-key-vault/store"

  mkdir -p "$BATS_TEST_TMPDIR/bin"

  cat > "$BATS_TEST_TMPDIR/bin/np" << 'EOF'
#!/bin/bash
entity_type="$1"
case "$entity_type" in
  organization) echo "\"acme\"" ;;
  account)      echo "\"prod\"" ;;
  namespace)    echo "\"billing\"" ;;
  application)  echo "\"api\"" ;;
  *)            echo "\"unknown\"" ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/np"

  export AZ_LOG="$BATS_TEST_TMPDIR/az.log"
  cat > "$BATS_TEST_TMPDIR/bin/az" << EOF
#!/bin/bash
echo "ARGS: \$@" >> "$AZ_LOG"
if [ "\${MOCK_AZ_EXIT:-0}" -ne 0 ]; then exit \$MOCK_AZ_EXIT; fi
echo "https://my-vault.vault.azure.net/secrets/some-name/abc123"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/az"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export AZ_VAULT_NAME="my-vault"
  export AZ_SECRET_PREFIX="parameters-"
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

@test "azure-key-vault store: external_id is canonical slash form + version suffix" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  # Mock URL ends in /abc123 — that's the version
  expected="organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/42#abc123"
  assert_equal "$external_id" "$expected"
}

@test "azure-key-vault store: secret_name uses dashes (AKV-safe)" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  secret_name=$(echo "$output" | jq -r '.metadata.secret_name')
  # AKV: / and = both become -
  assert_contains "$secret_name" "parameters-organization-acme-1255165411-account-prod-95118862"
  assert_contains "$secret_name" "-42"
  # Must not contain / or =
  [[ "$secret_name" != *"/"* ]]
  [[ "$secret_name" != *"="* ]]
}

@test "azure-key-vault store: calls az with AKV-safe name" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "keyvault secret set"
  assert_contains "$captured" "--vault-name my-vault"
  assert_contains "$captured" "--name parameters-organization-acme-1255165411"
  assert_contains "$captured" "--value my-secret"
}

@test "azure-key-vault store: dimensions sorted alphabetically in external_id" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.dimensions = {environment: "prod", country: "arg"}')

  run bash -c "$DEPS; source $SCRIPT"

  external_id=$(echo "$output" | jq -r '.external_id')
  assert_contains "$external_id" "country=arg/environment=prod/42"

  # AKV transformed name should have dashes
  secret_name=$(echo "$output" | jq -r '.metadata.secret_name')
  assert_contains "$secret_name" "country-arg-environment-prod-42"
}

@test "azure-key-vault store: fails with troubleshooting on az error" {
  run bash -c "$DEPS; MOCK_AZ_EXIT=1 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store secret in Azure Key Vault"
}
