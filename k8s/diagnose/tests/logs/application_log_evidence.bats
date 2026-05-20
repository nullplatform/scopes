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

# Helper: extract a field from the evidence JSON stored in SCRIPT_OUTPUT_FILE.
evidence() {
  jq -r "$1" "$SCRIPT_OUTPUT_FILE"
}

# =============================================================================
# Snapshot-unavailable path (no PROBLEMATIC_PODS_FILE)
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
# No problematic pods (file exists but empty)
# =============================================================================
@test "logs/application_log_evidence: success with empty result when no problematic pods" {
  : > "$PROBLEMATIC_PODS_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.status')" = "success" ]
  [ "$(evidence '.evidence.severity')" = "info" ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "0" ]
  [ "$(evidence '.evidence.details.containers_with_logs')" = "0" ]
  assert_contains "$(evidence '.evidence.summary')" "No problematic pods"
}

# =============================================================================
# One pod with current logs
# =============================================================================
@test "logs/application_log_evidence: collects current logs from one container with full context" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{
  "metadata":{"name":"pod-1"},
  "spec":{"containers":[{"name":"app"}]},
  "status":{
    "phase":"Running",
    "containerStatuses":[{
      "name":"app",
      "state":{"running":{}},
      "restartCount":0
    }]
  }
}]}
EOF
  printf 'line1\nline2\nERROR: boom\n' > "$POD_LOGS_DIR/pod-1.app.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.status')" = "success" ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "1" ]
  [ "$(evidence '.evidence.details.containers_with_logs')" = "1" ]
  [ "$(evidence '.evidence.details.logs[0].pod')" = "pod-1" ]
  [ "$(evidence '.evidence.details.logs[0].container')" = "app" ]
  [ "$(evidence '.evidence.details.logs[0].init_container')" = "false" ]
  # Context fields from the snapshot
  [ "$(evidence '.evidence.details.logs[0].pod_phase')" = "Running" ]
  [ "$(evidence '.evidence.details.logs[0].container_state')" = "running" ]
  [ "$(evidence '.evidence.details.logs[0].restart_count')" = "0" ]
  # Log content
  [ "$(evidence '.evidence.details.logs[0].current_logs | length')" = "3" ]
  [ "$(evidence '.evidence.details.logs[0].previous_logs | length')" = "0" ]
  assert_contains "$(evidence '.evidence.details.logs[0].current_logs | join("\n")')" "ERROR: boom"
  [ "$(evidence '.evidence.affected[0]')" = "pod-1" ]
}

@test "logs/application_log_evidence: surfaces CrashLoopBackOff context with last exit code meaning" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{
  "metadata":{"name":"pod-1"},
  "spec":{"containers":[{"name":"app"}]},
  "status":{
    "phase":"Running",
    "containerStatuses":[{
      "name":"app",
      "state":{"waiting":{"reason":"CrashLoopBackOff"}},
      "lastState":{"terminated":{"exitCode":137,"reason":"OOMKilled"}},
      "restartCount":5
    }]
  }
}]}
EOF
  echo "starting up..." > "$POD_LOGS_DIR/pod-1.app.log"
  echo "killed by OOM" > "$POD_LOGS_DIR/pod-1.app.previous.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.logs[0].container_state')" = "waiting" ]
  [ "$(evidence '.evidence.details.logs[0].current_state_reason')" = "CrashLoopBackOff" ]
  [ "$(evidence '.evidence.details.logs[0].restart_count')" = "5" ]
  [ "$(evidence '.evidence.details.logs[0].last_termination_reason')" = "OOMKilled" ]
  [ "$(evidence '.evidence.details.logs[0].last_exit_code')" = "137" ]
  # Reused exit_code_meaning from diagnose_utils
  assert_contains "$(evidence '.evidence.details.logs[0].last_exit_code_meaning')" "OOMKilled"
  # Previous logs hold the OOM evidence
  assert_contains "$(evidence '.evidence.details.logs[0].previous_logs[0]')" "killed by OOM"
}

@test "logs/application_log_evidence: surfaces pod_reason from Ready condition when not Ready" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{
  "metadata":{"name":"pod-1"},
  "spec":{"containers":[{"name":"app"}]},
  "status":{
    "phase":"Pending",
    "conditions":[
      {"type":"Ready","status":"False","reason":"ContainersNotReady"}
    ],
    "containerStatuses":[{
      "name":"app",
      "state":{"waiting":{"reason":"ContainerCreating"}},
      "restartCount":0
    }]
  }
}]}
EOF
  echo "creating" > "$POD_LOGS_DIR/pod-1.app.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.logs[0].pod_phase')" = "Pending" ]
  [ "$(evidence '.evidence.details.logs[0].pod_reason')" = "ContainersNotReady" ]
  [ "$(evidence '.evidence.details.logs[0].current_state_reason')" = "ContainerCreating" ]
}

# =============================================================================
# Current + previous logs
# =============================================================================
@test "logs/application_log_evidence: includes previous logs when available" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"app"}]}}]}
EOF
  echo "current run output" > "$POD_LOGS_DIR/pod-1.app.log"
  echo "previous crash output" > "$POD_LOGS_DIR/pod-1.app.previous.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.logs[0].current_logs | length')" = "1" ]
  [ "$(evidence '.evidence.details.logs[0].previous_logs | length')" = "1" ]
  assert_contains "$(evidence '.evidence.details.logs[0].previous_logs[0]')" "previous crash output"
}

# =============================================================================
# Init container
# =============================================================================
@test "logs/application_log_evidence: flags init container with init_container=true" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"initContainers":[{"name":"migrate"}],"containers":[{"name":"app"}]}}]}
EOF
  echo "running migrations" > "$POD_LOGS_DIR/pod-1.migrate.log"
  echo "app started" > "$POD_LOGS_DIR/pod-1.app.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.containers_with_logs')" = "2" ]
  # Init container appears with init_container=true
  local init_entry
  init_entry=$(jq -r '.evidence.details.logs[] | select(.container == "migrate") | .init_container' "$SCRIPT_OUTPUT_FILE")
  [ "$init_entry" = "true" ]
  # Regular container appears with init_container=false
  local regular_entry
  regular_entry=$(jq -r '.evidence.details.logs[] | select(.container == "app") | .init_container' "$SCRIPT_OUTPUT_FILE")
  [ "$regular_entry" = "false" ]
}

# =============================================================================
# Pod is problematic but has no logs (image never started)
# =============================================================================
@test "logs/application_log_evidence: surfaces 'no logs' when problematic pod produced none" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"app"}]}}]}
EOF
  # No log files at all (e.g. ImagePullBackOff → container never ran)

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.status')" = "success" ]
  [ "$(evidence '.evidence.severity')" = "info" ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "0" ]
  [ "$(evidence '.evidence.details.problematic_pod_count')" = "1" ]
  assert_contains "$(evidence '.evidence.summary')" "image may never have started"
}

# =============================================================================
# Multiple pods, mixed log availability
# =============================================================================
@test "logs/application_log_evidence: aggregates multiple pods and reports affected list" {
  printf 'pod-a\npod-b\npod-c\n' > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{
  "items":[
    {"metadata":{"name":"pod-a"},"spec":{"containers":[{"name":"app"}]}},
    {"metadata":{"name":"pod-b"},"spec":{"containers":[{"name":"app"}]}},
    {"metadata":{"name":"pod-c"},"spec":{"containers":[{"name":"app"}]}}
  ]
}
EOF
  echo "pod-a log line" > "$POD_LOGS_DIR/pod-a.app.log"
  echo "pod-c log line" > "$POD_LOGS_DIR/pod-c.app.log"
  # pod-b has no log file (image pull issue) — should still be counted as problematic

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "2" ]
  [ "$(evidence '.evidence.details.containers_with_logs')" = "2" ]
  [ "$(evidence '.evidence.details.problematic_pod_count')" = "3" ]
  # Affected only contains pods that produced logs (pod-a, pod-c), not pod-b
  local affected
  affected=$(evidence '.evidence.affected | sort | join(",")')
  [ "$affected" = "pod-a,pod-c" ]
}

# =============================================================================
# Empty log file (kubectl returned no output but the file exists)
# =============================================================================
@test "logs/application_log_evidence: skips containers whose log file is empty" {
  echo "pod-1" > "$PROBLEMATIC_PODS_FILE"
  cat > "$PODS_FILE" <<'EOF'
{"items":[{"metadata":{"name":"pod-1"},"spec":{"containers":[{"name":"app"}]}}]}
EOF
  : > "$POD_LOGS_DIR/pod-1.app.log"  # empty file

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../logs/application_log_evidence'"

  [ "$status" -eq 0 ]
  [ "$(evidence '.evidence.details.containers_with_logs')" = "0" ]
  [ "$(evidence '.evidence.details.pods_with_logs')" = "0" ]
}
