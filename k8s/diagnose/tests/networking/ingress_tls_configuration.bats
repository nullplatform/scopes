#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/networking/ingress_tls_configuration
# =============================================================================

strip_ansi() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export SCOPE_LABEL_SELECTOR="scope_id=123"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"
  export SCRIPT_LOG_FILE="$(mktemp)"
  export INGRESSES_FILE="$(mktemp)"
  export SECRETS_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$INGRESSES_FILE"
  rm -f "$SECRETS_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "networking/ingress_tls_configuration: success when TLS secret exists with correct type" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "tls": [{"secretName": "my-tls-secret", "hosts": ["app.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$SECRETS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-tls-secret", "annotations": {"tls.crt": "true", "tls.key": "true"}},
    "type": "kubernetes.io/tls"
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "TLS Secret: my-tls-secret (valid for hosts: app.example.com)"
  assert_contains "$stripped" "TLS configuration valid for all"
}

@test "networking/ingress_tls_configuration: updates check result to success" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "tls": [{"secretName": "my-tls-secret", "hosts": ["app.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$SECRETS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-tls-secret", "annotations": {"tls.crt": "true", "tls.key": "true"}},
    "type": "kubernetes.io/tls"
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "networking/ingress_tls_configuration: info when no TLS hosts configured" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  echo '{"items":[]}' > "$SECRETS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No TLS configuration (HTTP only)"
}

@test "networking/ingress_tls_configuration: error when TLS secret not found" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "tls": [{"secretName": "missing-secret", "hosts": ["app.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  echo '{"items":[]}' > "$SECRETS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "TLS Secret: 'missing-secret' not found in namespace"
}

@test "networking/ingress_tls_configuration: error when TLS secret has wrong type" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "tls": [{"secretName": "my-tls-secret", "hosts": ["app.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$SECRETS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-tls-secret", "annotations": {}},
    "type": "Opaque"
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "TLS Secret: my-tls-secret has wrong type 'Opaque' (expected kubernetes.io/tls)"
}

@test "networking/ingress_tls_configuration: updates check result to failed on issues" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "tls": [{"secretName": "missing-secret", "hosts": ["app.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  echo '{"items":[]}' > "$SECRETS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

@test "networking/ingress_tls_configuration: shows action when secret not found" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "tls": [{"secretName": "missing-secret", "hosts": ["app.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  echo '{"items":[]}' > "$SECRETS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Create TLS secret or update ingress configuration"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "networking/ingress_tls_configuration: skips when no ingresses" {
  echo '{"items":[]}' > "$INGRESSES_FILE"
  echo '{"items":[]}' > "$SECRETS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

@test "networking/ingress_tls_configuration: handles multiple TLS entries" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "tls": [
        {"secretName": "secret-1", "hosts": ["app1.example.com"]},
        {"secretName": "secret-2", "hosts": ["app2.example.com"]}
      ],
      "rules": [
        {"host": "app1.example.com"},
        {"host": "app2.example.com"}
      ]
    }
  }]
}
EOF
  cat > "$SECRETS_FILE" << 'EOF'
{
  "items": [
    {"metadata": {"name": "secret-1", "annotations": {"tls.crt": "true", "tls.key": "true"}}, "type": "kubernetes.io/tls"},
    {"metadata": {"name": "secret-2", "annotations": {"tls.crt": "true", "tls.key": "true"}}, "type": "kubernetes.io/tls"}
  ]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_tls_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Checking TLS configuration for ingress: my-ingress"
  assert_contains "$stripped" "TLS configuration valid for all"
}
