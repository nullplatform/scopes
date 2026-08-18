#!/usr/bin/env bats
# =============================================================================
# Unit tests for log/build_context
# Tests the filter extraction from NP_ACTION_CONTEXT, in particular the time
# range: end_time was never extracted, so log queries had no upper bound
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  BUILD_CONTEXT="$PROJECT_ROOT/k8s/log/build_context"
}

# Runs build_context with the given context and echoes one exported variable.
# build_context exits when APPLICATION_ID is missing, so it runs in a subshell.
extract() {
  local context="$1" variable="$2"
  NP_ACTION_CONTEXT="$context" bash -c "source '$BUILD_CONTEXT' >/dev/null 2>&1; echo \"\$$variable\""
}

full_context() {
  echo '{"notification":{"arguments":{
    "application_id":"26611171",
    "scope_id":"2075362883",
    "limit":100,
    "start_time":1786924800000,
    "end_time":1787011199000
  }}}'
}

# =============================================================================
# Time range extraction
# =============================================================================
@test "build_context: extracts both ends of the requested time range" {
  run extract "$(full_context)" START_TIME
  assert_equal "$output" "1786924800000"

  run extract "$(full_context)" END_TIME
  assert_equal "$output" "1787011199000"
}

@test "build_context: leaves END_TIME empty when the request has no upper bound" {
  local context='{"notification":{"arguments":{"application_id":"26611171","start_time":1786924800000}}}'

  run extract "$context" END_TIME
  assert_empty "$output"

  run extract "$context" START_TIME
  assert_equal "$output" "1786924800000"
}

# =============================================================================
# Remaining filters
# =============================================================================
@test "build_context: extracts the non-time filters" {
  run extract "$(full_context)" APPLICATION_ID
  assert_equal "$output" "26611171"

  run extract "$(full_context)" SCOPE_ID
  assert_equal "$output" "2075362883"

  run extract "$(full_context)" LIMIT
  assert_equal "$output" "100"
}

@test "build_context: fails when application_id is missing" {
  run bash -c "NP_ACTION_CONTEXT='{\"notification\":{\"arguments\":{}}}' source '$BUILD_CONTEXT'"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Missing required parameters: APPLICATION_ID"
}
