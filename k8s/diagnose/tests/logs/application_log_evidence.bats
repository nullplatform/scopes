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
  [ "$(evidence '.evidence.details.pods_with_logs')" = "0" ]
}

# =============================================================================
# No problematic pods
# =============================================================================
@test "logs/application_log_evidence: success with zero counters when no problematic pods" {
  : > "$PROBLEMATIC_PODS_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.status')" = "success" ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "0" ]
  [ "$(evidence '.evidence.details.problematic_pod_count')" = "0" ]
  assert_contains "$(evidence '.evidence.summary')" "No problematic pods"
}

# =============================================================================
# Focuses on the application container only — sidecars are not echoed
# =============================================================================
@test "logs/application_log_evidence: echoes only application logs (ignores sidecars)" {
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
  # Header + lines prefixed with "| " appear in stdout (captured by UI logs[])
  assert_contains "$output" "application log tail from pod-1"
  assert_contains "$output" "| starting..."
  assert_contains "$output" "| ERROR: missing DATABASE_URL"
  # Sidecar must NOT leak
  if [[ "$output" == *"nginx sidecar noise"* ]]; then
    echo "Sidecar log leaked into stdout"
    return 1
  fi
  # Affected lists the pod, counters reflect success
  [ "$(evidence '.evidence.affected[0]')" = "pod-1" ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "1" ]
  [ "$(evidence '.evidence.details.problematic_pod_count')" = "1" ]
}

# =============================================================================
# Evidence has NO log text — only counters
# =============================================================================
@test "logs/application_log_evidence: evidence.details exposes only counters, never log text" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"application"}]}}]}
EOF
  echo "secret log line that must not appear in evidence" > "$POD_LOGS_DIR/pod-1.application.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  # details has only the two counters, no pods array, no logs field
  local keys
  keys=$(jq -r '.evidence.details | keys | sort | join(",")' "$SCRIPT_OUTPUT_FILE")
  [ "$keys" = "pods_with_logs,problematic_pod_count" ]
  # The log text must not appear anywhere in the evidence object
  if [[ "$(jq -c '.evidence' "$SCRIPT_OUTPUT_FILE")" == *"secret log line"* ]]; then
    echo "Log text leaked into evidence"
    return 1
  fi
  # But it MUST appear in stdout
  assert_contains "$output" "| secret log line"
}

# =============================================================================
# Previous + current are merged into a single chronological stream on stdout
# =============================================================================
@test "logs/application_log_evidence: stdout shows previous logs first, then current" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"application"}]}}]}
EOF
  echo "current run" > "$POD_LOGS_DIR/pod-1.application.log"
  echo "previous crash output" > "$POD_LOGS_DIR/pod-1.application.previous.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  # Both lines must appear in stdout
  assert_contains "$output" "| previous crash output"
  assert_contains "$output" "| current run"
  # And previous must come before current
  local prev_line current_line
  prev_line=$(printf '%s\n' "$output" | grep -n "previous crash output" | head -1 | cut -d: -f1)
  current_line=$(printf '%s\n' "$output" | grep -n "current run" | head -1 | cut -d: -f1)
  [ "$prev_line" -lt "$current_line" ] || { echo "Expected previous to print before current"; return 1; }
}

# =============================================================================
# Caps logs to last 50 lines (EVIDENCE_LOG_TAIL_LINES default)
# =============================================================================
@test "logs/application_log_evidence: caps echoed logs to the last 50 lines" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"application"}]}}]}
EOF
  for i in $(seq 1 30); do echo "prev-$i" >> "$POD_LOGS_DIR/pod-1.application.previous.log"; done
  for i in $(seq 1 30); do echo "curr-$i" >> "$POD_LOGS_DIR/pod-1.application.log"; done

  export EVIDENCE_LOG_TAIL_LINES=50

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  # 60 input lines, capped at 50 → the first 10 previous lines must drop off
  if [[ "$output" == *"| prev-1"$'\n'* || "$output" == *"| prev-1 "* ]]; then
    : # 'prev-1' is a prefix of 'prev-10', need stricter match
  fi
  # Stricter check: 'prev-10' should not appear because only prev-11..30 + curr-1..30 fit
  if printf '%s\n' "$output" | grep -qE '\| prev-10$'; then
    echo "Expected prev-10 to be dropped (out of tail-50 window)"
    return 1
  fi
  # But prev-11 should be there (first survivor)
  printf '%s\n' "$output" | grep -qE '\| prev-11$' || { echo "Expected prev-11 to survive"; return 1; }
  # And the latest current line is the last visible
  printf '%s\n' "$output" | grep -qE '\| curr-30$' || { echo "Expected curr-30 to survive"; return 1; }
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
  [ "$(evidence '.evidence.details.pods_with_logs')" = "0" ]
  [ "$(evidence '.evidence.details.problematic_pod_count')" = "1" ]
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
  # No log files

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "0" ]
  assert_contains "$(evidence '.evidence.summary')" "image may never have started"
}

# =============================================================================
# Multiple pods aggregated
# =============================================================================
@test "logs/application_log_evidence: aggregates affected across multiple pods" {
  printf 'pod-a\npod-b\npod-c\n' > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{
  "items":[
    {"metadata":{"name":"pod-a"},"spec":{"containers":[{"name":"application"}]}},
    {"metadata":{"name":"pod-b"},"spec":{"containers":[{"name":"application"}]}},
    {"metadata":{"name":"pod-c"},"spec":{"containers":[{"name":"application"}]}}
  ]
}
EOF
  echo "log of A" > "$POD_LOGS_DIR/pod-a.application.log"
  echo "log of C" > "$POD_LOGS_DIR/pod-c.application.log"
  # pod-b has no log file

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "2" ]
  [ "$(evidence '.evidence.details.problematic_pod_count')" = "3" ]
  local affected
  affected=$(evidence '.evidence.affected | sort | join(",")')
  [ "$affected" = "pod-a,pod-c" ]
  # Both visible in stdout, pod-b absent
  assert_contains "$output" "| log of A"
  assert_contains "$output" "| log of C"
}
