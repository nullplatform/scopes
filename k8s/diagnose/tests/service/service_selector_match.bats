#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/service/service_selector_match
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export LABEL_SELECTOR="app=test"
  export DEPLOYMENT_ID="deploy-123"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  export SERVICES_FILE="$(mktemp)"
  export PODS_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$SERVICES_FILE"
  rm -f "$PODS_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "service/service_selector_match: success when selectors match" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "myapp", "version": "v1"}
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "pod-1",
      "labels": {"app": "myapp", "version": "v1"}
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_selector_match'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Selector matches"
  assert_contains "$output" "pod(s)"
}

@test "service/service_selector_match: matches multiple pods" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "myapp"}}
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [
    {"metadata": {"name": "pod-1", "labels": {"app": "myapp"}}},
    {"metadata": {"name": "pod-2", "labels": {"app": "myapp"}}}
  ]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_selector_match'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Selector matches"
  assert_contains "$output" "2"
  assert_contains "$output" "pod(s)"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "service/service_selector_match: fails when no selector defined" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {}
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_selector_match'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "No selector defined"
}

@test "service/service_selector_match: fails when no pods match" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "myapp"}}
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "pod-1",
      "labels": {"app": "different-app", "deployment_id": "deploy-123"}
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_selector_match'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "No pods match selector"
}

@test "service/service_selector_match: shows existing pods when mismatch" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "myapp"}}
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "existing-pod",
      "labels": {"app": "other", "deployment_id": "deploy-123"}
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_selector_match'"

  assert_contains "$output" "Existing pods"
  assert_contains "$output" "existing-pod"
}

@test "service/service_selector_match: shows action to verify labels" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "myapp"}}
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "pod-1",
      "labels": {"app": "wrong", "deployment_id": "deploy-123"}
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_selector_match'"

  assert_contains "$output" "🔧"
  assert_contains "$output" "Verify pod labels"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "service/service_selector_match: skips when no services" {
  echo '{"items":[]}' > "$SERVICES_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_selector_match'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

# =============================================================================
# Status Update Tests
# =============================================================================
@test "service/service_selector_match: updates status to failed on mismatch" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "myapp"}}
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  source "$BATS_TEST_DIRNAME/../../service/service_selector_match"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}
