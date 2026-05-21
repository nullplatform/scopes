#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/logs/application_log_evidence
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

  export PODS_FILE="$(mktemp)"
  export DATA_DIR="$(mktemp -d)"
  export POD_LOGS_DIR="$DATA_DIR/pod_logs"
  export PROBLEMATIC_PODS_FILE="$DATA_DIR/problematic_pods.txt"
  mkdir -p "$POD_LOGS_DIR"
  export EVIDENCE_LOG_TAIL_LINES=50
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR" "$DATA_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE" "$SCRIPT_LOG_FILE" "$PODS_FILE"
}

evidence() {
  jq -r "$1" "$SCRIPT_OUTPUT_FILE"
}

# =============================================================================
# Snapshot-unavailable path
# =============================================================================
@test "logs/application_log_evidence: skipped when PROBLEMATIC_PODS_FILE missing" {
  rm -f "$PROBLEMATIC_PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.status')" = "skipped" ]
  [ "$(evidence '.evidence.severity')" = "info" ]
  [ "$(evidence '.evidence.details.pods | length')" = "0" ]
}

# =============================================================================
# No problematic pods
# =============================================================================
@test "logs/application_log_evidence: success with empty payload when no problematic pods" {
  : > "$PROBLEMATIC_PODS_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.status')" = "success" ]
  [ "$(evidence '.evidence.details.pods | length')" = "0" ]
  assert_contains "$(evidence '.evidence.summary')" "No problematic pods"
}

# =============================================================================
# Focuses on the application container only
# =============================================================================
@test "logs/application_log_evidence: collects only application container logs (ignores sidecars)" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{
  "metadata":{"name":"pod-1"},
  "spec":{"containers":[{"name":"http"},{"name":"application"}]}
}]}
EOF
  echo "nginx sidecar noise" > "$POD_LOGS_DIR/pod-1.http.log"
  printf 'starting...\nERROR: missing DATABASE_URL\n' > "$POD_LOGS_DIR/pod-1.application.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.pods | length')" = "1" ]
  [ "$(evidence '.evidence.details.pods[0].pod')" = "pod-1" ]
  [ "$(evidence '.evidence.details.pods[0].logs | length')" = "2" ]
  # Application log must appear, sidecar log must NOT
  assert_contains "$(evidence '.evidence.details.pods[0].logs | join("\n")')" "missing DATABASE_URL"
  if [[ "$(evidence '.evidence.details | tostring')" == *"nginx sidecar noise"* ]]; then
    echo "Sidecar log leaked into evidence"
    return 1
  fi
  # No leftover metadata fields from the previous shape (no current/previous split either)
  for field in pod_phase pod_reason container init_container container_state restart_count last_exit_code current_logs previous_logs; do
    if [[ "$(evidence ".evidence.details.pods[0].$field")" != "null" ]]; then
      echo "Unexpected leftover field: $field"
      return 1
    fi
  done
}

# =============================================================================
# Previous + current are merged into a single chronological logs array
# =============================================================================
@test "logs/application_log_evidence: merges previous and current logs in chronological order" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"application"}]}}]}
EOF
  echo "current run" > "$POD_LOGS_DIR/pod-1.application.log"
  echo "previous crash output" > "$POD_LOGS_DIR/pod-1.application.previous.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  # Single flat logs array, previous first (older) then current (newer)
  [ "$(evidence '.evidence.details.pods[0].logs | length')" = "2" ]
  [ "$(evidence '.evidence.details.pods[0].logs[0]')" = "previous crash output" ]
  [ "$(evidence '.evidence.details.pods[0].logs[1]')" = "current run" ]
}

@test "logs/application_log_evidence: caps logs to the last 50 lines (EVIDENCE_LOG_TAIL_LINES default)" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"application"}]}}]}
EOF
  # 30 previous + 30 current = 60 lines combined; only last 50 must survive
  for i in $(seq 1 30); do echo "prev-$i" >> "$POD_LOGS_DIR/pod-1.application.previous.log"; done
  for i in $(seq 1 30); do echo "curr-$i" >> "$POD_LOGS_DIR/pod-1.application.log"; done

  export EVIDENCE_LOG_TAIL_LINES=50

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.pods[0].logs | length')" = "50" ]
  # Should keep the latest 50 — the first 10 previous lines drop off
  [ "$(evidence '.evidence.details.pods[0].logs[0]')" = "prev-11" ]
  [ "$(evidence '.evidence.details.pods[0].logs[-1]')" = "curr-30" ]
}

# =============================================================================
# Pod without application container is skipped
# =============================================================================
@test "logs/application_log_evidence: skips pods that have no application container" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"sidecar-only"}]}}]}
EOF
  echo "irrelevant" > "$POD_LOGS_DIR/pod-1.sidecar-only.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.pods | length')" = "0" ]
  assert_contains "$(evidence '.evidence.summary')" "No application logs available"
}

# =============================================================================
# Pod has application container but it produced no logs
# =============================================================================
@test "logs/application_log_evidence: drops pod whose application container has no logs" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"application"}]}}]}
EOF
  # No log files (e.g. ImagePullBackOff)

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.pods | length')" = "0" ]
  assert_contains "$(evidence '.evidence.summary')" "image may never have started"
}

# =============================================================================
# Multiple pods aggregated
# =============================================================================
@test "logs/application_log_evidence: aggregates application logs across multiple pods" {
  printf 'pod-a\npod-b\npod-c\n' > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{
  "items":[
    {"metadata":{"name":"pod-a"},"spec":{"containers":[{"name":"http"},{"name":"application"}]}},
    {"metadata":{"name":"pod-b"},"spec":{"containers":[{"name":"http"},{"name":"application"}]}},
    {"metadata":{"name":"pod-c"},"spec":{"containers":[{"name":"http"},{"name":"application"}]}}
  ]
}
EOF
  echo "log of A" > "$POD_LOGS_DIR/pod-a.application.log"
  echo "log of C" > "$POD_LOGS_DIR/pod-c.application.log"
  # pod-b has no application log file → dropped silently

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.pods | length')" = "2" ]
  local affected
  affected=$(evidence '.evidence.affected | sort | join(",")')
  [ "$affected" = "pod-a,pod-c" ]
}

# =============================================================================
# Schema sanity: only the documented top-level fields are present
# =============================================================================
@test "logs/application_log_evidence: pod entry exposes exactly {pod, logs}" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"application"}]}}]}
EOF
  echo "a line" > "$POD_LOGS_DIR/pod-1.application.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  local keys
  keys=$(jq -r '.evidence.details.pods[0] | keys | sort | join(",")' "$SCRIPT_OUTPUT_FILE")
  [ "$keys" = "logs,pod" ]
}
