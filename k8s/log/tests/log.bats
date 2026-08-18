#!/usr/bin/env bats
# =============================================================================
# Unit tests for log/log
# Tests the epoch-to-ISO conversion and the flags handed to kube-logger, with
# the kube-logger binary replaced by a stub that echoes its arguments
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  LOG_SCRIPT="$PROJECT_ROOT/k8s/log/log"

  # Stand in for the kube-logger binary at the path the script derives
  STUB_ROOT="$(mktemp -d)"
  local platform arch
  platform="$(uname | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  [ "$arch" = "aarch64" ] && arch="arm64"
  mkdir -p "$STUB_ROOT/log/kube-logger-go/bin/$platform"
  printf '#!/usr/bin/env bash\necho "$@"\n' > "$STUB_ROOT/log/kube-logger-go/bin/$platform/exec-$arch"
  chmod +x "$STUB_ROOT/log/kube-logger-go/bin/$platform/exec-$arch"

  export SERVICE_PATH="$STUB_ROOT"
  export APPLICATION_ID="26611171"
  export SCOPE_ID="2075362883"

  # epoch_ms_to_iso is defined inside the script; extract it for isolated testing
  eval "$(sed -n '/^epoch_ms_to_iso()/,/^}/p' "$LOG_SCRIPT")"
}

teardown() {
  unset -f epoch_ms_to_iso 2>/dev/null || true
  unset SERVICE_PATH APPLICATION_ID SCOPE_ID START_TIME END_TIME 2>/dev/null || true
  [ -n "$STUB_ROOT" ] && rm -rf "$STUB_ROOT"
}

# =============================================================================
# epoch_ms_to_iso
# =============================================================================
@test "epoch_ms_to_iso: converts epoch milliseconds to ISO-8601 UTC" {
  run epoch_ms_to_iso 1786924800000
  [ "$status" -eq 0 ]
  assert_equal "$output" "2026-08-17T00:00:00Z"
}

@test "epoch_ms_to_iso: rejects a non-numeric timestamp" {
  # bc reads bare words as variables and evaluates them to 0, so this used to
  # convert to 1970 instead of failing: another window the user never asked for.
  run epoch_ms_to_iso "not-a-timestamp"
  [ "$status" -ne 0 ]
  assert_contains "$output" "not epoch milliseconds"
  [[ "$output" != *"1970-"* ]]
}

@test "epoch_ms_to_iso: never answers with the current time" {
  # A bound that cannot be converted must not silently become "now".
  run epoch_ms_to_iso ""
  [ "$status" -ne 0 ]
  [[ "$output" != *"$(date -u +%Y-%m-%d)"* ]]
}

# =============================================================================
# Flags handed to kube-logger
# =============================================================================
@test "log: passes both ends of the range to kube-logger" {
  export START_TIME=1786924800000
  export END_TIME=1787011199000

  run bash "$LOG_SCRIPT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "--start-time 2026-08-17T00:00:00Z"
  assert_contains "$output" "--end-time 2026-08-17T23:59:59Z"
}

@test "log: omits --end-time when the request has no upper bound" {
  export START_TIME=1786924800000

  run bash "$LOG_SCRIPT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "--start-time 2026-08-17T00:00:00Z"
  [[ "$output" != *"--end-time"* ]]
}

@test "log: fails when a supplied bound cannot be converted" {
  export START_TIME="not-a-timestamp"

  run bash "$LOG_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" != *"--start-time"* ]]
}
