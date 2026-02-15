#!/usr/bin/env bats
# Unit tests for diagnose/notify_check_running

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../utils/diagnose_utils"

  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
}

@test "notify_check_running: sets status to running" {
  source "$BATS_TEST_DIRNAME/../notify_check_running"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "running"
}

@test "notify_check_running: sets empty evidence" {
  source "$BATS_TEST_DIRNAME/../notify_check_running"

  result=$(jq -c '.evidence' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "{}"
}

@test "notify_check_running: sets start_at timestamp" {
  source "$BATS_TEST_DIRNAME/../notify_check_running"

  start_at=$(jq -r '.start_at' "$SCRIPT_OUTPUT_FILE")
  assert_not_empty "$start_at"
  # Should be ISO 8601 format with T and Z
  assert_contains "$start_at" "T"
  assert_contains "$start_at" "Z"
}

@test "notify_check_running: fails when SCRIPT_OUTPUT_FILE missing" {
  rm -f "$SCRIPT_OUTPUT_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../notify_check_running'"

  [ "$status" -ne 0 ]
  assert_contains "$output" "File not found"
}
