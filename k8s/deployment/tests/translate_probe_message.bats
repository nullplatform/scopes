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
