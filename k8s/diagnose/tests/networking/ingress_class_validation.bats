#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/networking/ingress_class_validation
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
  export INGRESSCLASSES_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$INGRESSES_FILE"
  rm -f "$INGRESSCLASSES_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "networking/ingress_class_validation: success with valid ingressClassName" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"ingressClassName": "alb"}
  }]
}
EOF
  cat > "$INGRESSCLASSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "alb"}
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_class_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "IngressClass 'alb' is valid"
}

@test "networking/ingress_class_validation: success with default class" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {}
  }]
}
EOF
  cat > "$INGRESSCLASSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "nginx",
      "annotations": {
        "ingressclass.kubernetes.io/is-default-class": "true"
      }
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_class_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Using default IngressClass"
  assert_contains "$output" "nginx"
}

@test "networking/ingress_class_validation: handles deprecated annotation" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "kubernetes.io/ingress.class": "alb"
      }
    },
    "spec": {}
  }]
}
EOF
  cat > "$INGRESSCLASSES_FILE" << 'EOF'
{
  "items": [{"metadata": {"name": "alb"}}]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_class_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "deprecated annotation"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "networking/ingress_class_validation: fails when class not found" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"ingressClassName": "nonexistent"}
  }]
}
EOF
  cat > "$INGRESSCLASSES_FILE" << 'EOF'
{
  "items": [{"metadata": {"name": "alb"}}]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_class_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "IngressClass 'nonexistent' not found"
}

@test "networking/ingress_class_validation: shows available classes on failure" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"ingressClassName": "wrong"}
  }]
}
EOF
  cat > "$INGRESSCLASSES_FILE" << 'EOF'
{
  "items": [
    {"metadata": {"name": "alb"}},
    {"metadata": {"name": "nginx"}}
  ]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_class_validation'"

  assert_contains "$output" "Available classes:"
  assert_contains "$output" "alb"
  assert_contains "$output" "nginx"
}

@test "networking/ingress_class_validation: fails when no class and no default" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {}
  }]
}
EOF
  cat > "$INGRESSCLASSES_FILE" << 'EOF'
{
  "items": [{"metadata": {"name": "alb"}}]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_class_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "No IngressClass specified"
  assert_contains "$output" "no default found"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "networking/ingress_class_validation: skips when no ingresses" {
  echo '{"items":[]}' > "$INGRESSES_FILE"
  echo '{"items":[]}' > "$INGRESSCLASSES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_class_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

# =============================================================================
# Status Update Tests
# =============================================================================
@test "networking/ingress_class_validation: updates status to failed on invalid class" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"ingressClassName": "invalid"}
  }]
}
EOF
  echo '{"items":[]}' > "$INGRESSCLASSES_FILE"

  source "$BATS_TEST_DIRNAME/../../networking/ingress_class_validation"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}
