#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/service/service_existence
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export LABEL_SELECTOR="app=test"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  export SERVICES_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$SERVICES_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "service/service_existence: success when services found" {
  echo '{"items":[{"metadata":{"name":"svc-1"}},{"metadata":{"name":"svc-2"}}]}' > "$SERVICES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_existence'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "service(s)"
  assert_contains "$output" "svc-1"
  assert_contains "$output" "svc-2"
}

@test "service/service_existence: updates check result to success" {
  echo '{"items":[{"metadata":{"name":"svc-1"}}]}' > "$SERVICES_FILE"

  source "$BATS_TEST_DIRNAME/../../service/service_existence"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "service/service_existence: fails when no services found" {
  echo '{"items":[]}' > "$SERVICES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_existence'"

  [ "$status" -eq 1 ]
  assert_contains "$output" "No services found"
  assert_contains "$output" "$LABEL_SELECTOR"
}

@test "service/service_existence: shows action when no services" {
  echo '{"items":[]}' > "$SERVICES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_existence'"

  assert_contains "$output" "🔧"
  assert_contains "$output" "Create service"
}

@test "service/service_existence: updates check result to failed" {
  echo '{"items":[]}' > "$SERVICES_FILE"

  source "$BATS_TEST_DIRNAME/../../service/service_existence" || true

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "service/service_existence: handles single service" {
  echo '{"items":[{"metadata":{"name":"my-service"}}]}' > "$SERVICES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_existence'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "service(s)"
  assert_contains "$output" "my-service"
}
