#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/networking/ingress_existence
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export SCOPE_LABEL_SELECTOR="scope_id=123"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  export INGRESSES_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$INGRESSES_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "networking/ingress_existence: success when ingresses found" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{"host": "api.example.com"}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_existence'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "ingress(es)"
  assert_contains "$output" "my-ingress"
}

@test "networking/ingress_existence: shows hosts for each ingress" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [
        {"host": "api.example.com"},
        {"host": "www.example.com"}
      ]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_existence'"

  assert_contains "$output" "api.example.com"
  assert_contains "$output" "www.example.com"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "networking/ingress_existence: fails when no ingresses" {
  echo '{"items":[]}' > "$INGRESSES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_existence'"

  [ "$status" -eq 1 ]
  assert_contains "$output" "No ingresses found"
}

@test "networking/ingress_existence: shows action when no ingresses" {
  echo '{"items":[]}' > "$INGRESSES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_existence'"

  assert_contains "$output" "🔧"
  assert_contains "$output" "Create ingress"
}

@test "networking/ingress_existence: updates check result to failed" {
  echo '{"items":[]}' > "$INGRESSES_FILE"

  source "$BATS_TEST_DIRNAME/../../networking/ingress_existence" || true

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Multiple Ingresses Tests
# =============================================================================
@test "networking/ingress_existence: handles multiple ingresses" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [
    {"metadata": {"name": "ing-1"}, "spec": {"rules": [{"host": "a.com"}]}},
    {"metadata": {"name": "ing-2"}, "spec": {"rules": [{"host": "b.com"}]}}
  ]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_existence'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "ingress(es)"
  assert_contains "$output" "ing-1"
  assert_contains "$output" "ing-2"
}
