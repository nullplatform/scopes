#!/usr/bin/env bats
# Unit tests for diagnose/notify_diagnose_results

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../utils/diagnose_utils"

  export NP_OUTPUT_DIR="$(mktemp -d)"
  export NP_ACTION_CONTEXT='{
    "notification": {
      "id": "action-123",
      "service": {"id": "service-456"}
    }
  }'

  # Mock np CLI
  np() {
    echo "np called with: $*" >&2
    return 0
  }
  export -f np
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  unset NP_OUTPUT_DIR
  unset NP_ACTION_CONTEXT
  unset -f np
}

@test "notify_diagnose_results: fails when no JSON files exist" {
  run bash -c "source '$BATS_TEST_DIRNAME/../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../notify_diagnose_results'"

  [ "$status" -eq 1 ]
  assert_contains "$output" "No JSON result files found"
}

@test "notify_diagnose_results: succeeds when JSON files exist" {
  # Create a test JSON result file
  echo '{"category":"scope","status":"success","evidence":{}}' > "$NP_OUTPUT_DIR/test_check.json"

  run bash -c "source '$BATS_TEST_DIRNAME/../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../notify_diagnose_results'"

  [ "$status" -eq 0 ]
}

@test "notify_diagnose_results: calls np service action patch" {
  # Create a test JSON result file
  echo '{"category":"scope","status":"success","evidence":{}}' > "$NP_OUTPUT_DIR/test_check.json"

  # Capture np calls
  np() {
    echo "NP_CALLED: $*"
    return 0
  }
  export -f np

  run bash -c "source '$BATS_TEST_DIRNAME/../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../notify_diagnose_results'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "service action patch"
}

@test "notify_diagnose_results: excludes files in data directory" {
  # Create data directory with JSON file that should be excluded
  mkdir -p "$NP_OUTPUT_DIR/data"
  echo '{"should":"be excluded"}' > "$NP_OUTPUT_DIR/data/pods.json"

  # No other JSON files - should fail
  run bash -c "source '$BATS_TEST_DIRNAME/../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../notify_diagnose_results'"

  [ "$status" -eq 1 ]
  assert_contains "$output" "No JSON result files found"
}

@test "notify_diagnose_results: processes multiple check results" {
  # Create multiple check result files
  echo '{"category":"scope","status":"success","evidence":{}}' > "$NP_OUTPUT_DIR/check1.json"
  echo '{"category":"service","status":"failed","evidence":{}}' > "$NP_OUTPUT_DIR/check2.json"

  run bash -c "source '$BATS_TEST_DIRNAME/../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../notify_diagnose_results'"

  [ "$status" -eq 0 ]
}
