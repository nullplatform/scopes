#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/translate_probe_message - K8s probe message parser
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../translate_probe_message"
}

# -----------------------------------------------------------------------------
# Connection refused
# -----------------------------------------------------------------------------
@test "translate_probe_message: startup probe connection refused with path" {
  run translate_probe_message 'Startup probe failed: Get "http://10.15.28.102:8080/health": dial tcp 10.15.28.102:8080: connect: connection refused'

  [ "$status" -eq 0 ]
  assert_contains "$output" "Startup probe"
  assert_contains "$output" "not yet listening"
  assert_contains "$output" "/health"
}

@test "translate_probe_message: liveness probe connection refused" {
  run translate_probe_message 'Liveness probe failed: Get "http://10.0.0.5:8080/ping": dial tcp: connect: connection refused'

  [ "$status" -eq 0 ]
  assert_contains "$output" "Liveness probe"
  assert_contains "$output" "not yet listening"
  assert_contains "$output" "/ping"
}

# -----------------------------------------------------------------------------
# HTTP status codes
# -----------------------------------------------------------------------------
@test "translate_probe_message: startup probe HTTP 502" {
  run translate_probe_message 'Startup probe failed: HTTP probe failed with statuscode: 502'

  [ "$status" -eq 0 ]
  assert_contains "$output" "Startup probe"
  assert_contains "$output" "HTTP 502"
}

@test "translate_probe_message: readiness probe HTTP 404" {
  run translate_probe_message 'Readiness probe failed: HTTP probe failed with statuscode: 404'

  [ "$status" -eq 0 ]
  assert_contains "$output" "Readiness probe"
  assert_contains "$output" "HTTP 404"
}

# -----------------------------------------------------------------------------
# Timeout
# -----------------------------------------------------------------------------
@test "translate_probe_message: startup probe timeout" {
  run translate_probe_message 'Startup probe failed: Get "http://10.0.0.5:8080/health": context deadline exceeded (Client.Timeout exceeded while awaiting headers)'

  [ "$status" -eq 0 ]
  assert_contains "$output" "Startup probe"
  assert_contains "$output" "timed out"
  assert_contains "$output" "/health"
}

# -----------------------------------------------------------------------------
# Non-probe messages
# -----------------------------------------------------------------------------
@test "translate_probe_message: returns non-zero for non-probe messages" {
  run translate_probe_message 'Failed to pull image "nginx:latest"'

  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "translate_probe_message: returns non-zero for empty input" {
  run translate_probe_message ''

  [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Fallback for unknown probe failure shapes
# -----------------------------------------------------------------------------
@test "translate_probe_message: generic fallback when probe failure mode is unrecognized" {
  run translate_probe_message 'Startup probe failed: some weird new error format'

  [ "$status" -eq 0 ]
  assert_contains "$output" "Startup probe"
}

# -----------------------------------------------------------------------------
# parse_probe_message — structured output for consolidation
# -----------------------------------------------------------------------------
@test "parse_probe_message: emits pipe-separated kind, path, mode for connection refused" {
  run parse_probe_message 'Startup probe failed: Get "http://10.0.0.1:8080/health": dial tcp: connect: connection refused'

  [ "$status" -eq 0 ]
  [ "$output" = "Startup|/health|not yet listening" ]
}

@test "parse_probe_message: emits 'responded HTTP <code>' mode with empty path field preserved" {
  run parse_probe_message 'Startup probe failed: HTTP probe failed with statuscode: 502'

  [ "$status" -eq 0 ]
  # Empty path between two pipes must be preserved so callers can read 3 fields.
  # Mode reads as a verb so it composes inline with other modes in one sentence.
  [ "$output" = "Startup||responded HTTP 502 (expected 2xx)" ]
}

@test "parse_probe_message: returns non-zero for non-probe input" {
  run parse_probe_message 'Failed to pull image'
  [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# short_pod_name — strip K8S_DEPLOYMENT_NAME prefix
# -----------------------------------------------------------------------------
@test "short_pod_name: strips deployment prefix and marks truncation with '...'" {
  K8S_DEPLOYMENT_NAME="d-326230662-1916903584"
  run short_pod_name "d-326230662-1916903584-8578df9b4c-hhshq"

  [ "$status" -eq 0 ]
  # Leading '...' tells the operator the name was shortened
  [ "$output" = "...8578df9b4c-hhshq" ]
}

@test "short_pod_name: returns full name when prefix env is unset" {
  unset K8S_DEPLOYMENT_NAME
  run short_pod_name "some-pod-name-abc"

  [ "$status" -eq 0 ]
  [ "$output" = "some-pod-name-abc" ]
}

@test "short_pod_name: returns full name when pod does not match the prefix" {
  K8S_DEPLOYMENT_NAME="d-1-2"
  run short_pod_name "unrelated-pod-xyz"

  [ "$status" -eq 0 ]
  [ "$output" = "unrelated-pod-xyz" ]
}
