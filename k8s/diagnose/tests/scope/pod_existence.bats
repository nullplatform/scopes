#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/pod_existence - pod existence verification
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  # Setup required environment
  export NAMESPACE="test-ns"
  export LABEL_SELECTOR="app=test"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  # Create pods file
  export PODS_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$PODS_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "scope/pod_existence: success when pods found" {
  echo '{"items":[{"metadata":{"name":"pod-1"}},{"metadata":{"name":"pod-2"}}]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_existence'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "pod(s)"
  assert_contains "$output" "pod-1"
  assert_contains "$output" "pod-2"
}

@test "scope/pod_existence: updates check result to success" {
  echo '{"items":[{"metadata":{"name":"pod-1"}}]}' > "$PODS_FILE"

  source "$BATS_TEST_DIRNAME/../../scope/pod_existence"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "scope/pod_existence: fails when no pods found" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_existence'"

  [ "$status" -eq 1 ]
  assert_contains "$output" "No pods found"
  assert_contains "$output" "$LABEL_SELECTOR"
  assert_contains "$output" "$NAMESPACE"
}

@test "scope/pod_existence: shows action when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_existence'"

  assert_contains "$output" "🔧"
  assert_contains "$output" "Check deployment status"
}

@test "scope/pod_existence: updates check result to failed when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  source "$BATS_TEST_DIRNAME/../../scope/pod_existence" || true

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "scope/pod_existence: handles single pod" {
  echo '{"items":[{"metadata":{"name":"single-pod"}}]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_existence'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "pod(s)"
  assert_contains "$output" "single-pod"
}

@test "scope/pod_existence: handles malformed JSON gracefully" {
  echo 'not-valid-json' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_existence'"

  [ "$status" -eq 1 ]
  assert_contains "$output" "No pods found"
}
