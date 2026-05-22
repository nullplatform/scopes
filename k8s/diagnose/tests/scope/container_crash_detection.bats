#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/container_crash_detection
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

  # Mock kubectl logs
  kubectl() {
    echo "Application startup error"
    echo "Exception: NullPointerException"
  }
  export -f kubectl
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$PODS_FILE"
  unset -f kubectl
}

# =============================================================================
# Success Tests
# =============================================================================
@test "scope/container_crash_detection: success when no crashes" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "restartCount": 0,
        "state": {"running": {}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "running without crashes"
}

# =============================================================================
# CrashLoopBackOff Tests
# =============================================================================
@test "scope/container_crash_detection: detects CrashLoopBackOff" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "restartCount": 5,
        "state": {"waiting": {"reason": "CrashLoopBackOff"}},
        "lastState": {"terminated": {"exitCode": 1, "reason": "Error"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "CrashLoopBackOff"
  assert_contains "$output" "pod-1"
}

@test "scope/container_crash_detection: shows exit code details" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "restartCount": 3,
        "state": {"waiting": {"reason": "CrashLoopBackOff"}},
        "lastState": {"terminated": {"exitCode": 137, "reason": "OOMKilled"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  assert_contains "$output" "Exit Code: 137"
  assert_contains "$output" "OOMKilled"
  assert_contains "$output" "out of memory"
}

@test "scope/container_crash_detection: explains common exit codes" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "restartCount": 2,
        "state": {"waiting": {"reason": "CrashLoopBackOff"}},
        "lastState": {"terminated": {"exitCode": 143, "reason": "SIGTERM"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  assert_contains "$output" "143"
  assert_contains "$output" "graceful termination"
}

# =============================================================================
# Terminated Container Tests
# =============================================================================
@test "scope/container_crash_detection: detects terminated containers" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "restartCount": 0,
        "state": {"terminated": {"exitCode": 1, "reason": "Error"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  assert_contains "$output" "Terminated container"
}

@test "scope/container_crash_detection: handles clean exit (exit 0)" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "job-pod"},
    "status": {
      "containerStatuses": [{
        "name": "job",
        "restartCount": 0,
        "state": {"terminated": {"exitCode": 0, "reason": "Completed"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  assert_contains "$output" "Exit 0"
  assert_contains "$output" "Clean exit"
}

# =============================================================================
# High Restart Count Tests
# =============================================================================
@test "scope/container_crash_detection: warns on high restart count" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "restartCount": 5,
        "state": {"running": {}},
        "lastState": {"terminated": {"exitCode": 1, "reason": "Error"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  assert_contains "$output" "high restart count"
  assert_contains "$output" "Restarts: 5"
}

@test "scope/container_crash_detection: shows action for intermittent issues" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "restartCount": 10,
        "state": {"running": {}},
        "lastState": {"terminated": {"exitCode": 137, "reason": "OOMKilled"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  assert_contains "$output" "🔧"
  assert_contains "$output" "intermittent"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "scope/container_crash_detection: skips when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_crash_detection'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

# =============================================================================
# Status Update Tests
# =============================================================================
@test "scope/container_crash_detection: updates status to failed on crash" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "restartCount": 3,
        "state": {"waiting": {"reason": "CrashLoopBackOff"}},
        "lastState": {"terminated": {"exitCode": 1}}
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/container_crash_detection"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Evidence Schema Tests
# =============================================================================
@test "scope/container_crash_detection: success evidence follows schema" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "healthy-pod"},
    "status": {"containerStatuses": [{"name": "app", "ready": true, "restartCount": 0, "state": {"running": {}}}]}
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/container_crash_detection"

  severity=$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$severity" "info"

  summary=$(jq -r '.evidence.summary' "$SCRIPT_OUTPUT_FILE")
  assert_contains "$summary" "running without crashes"

  affected=$(jq -c '.evidence.affected' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$affected" "[]"

  pods_checked=$(jq -r '.evidence.details.pods_checked' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$pods_checked" "1"
}

@test "scope/container_crash_detection: failed evidence includes affected pods and crash details" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [
    {
      "metadata": {"name": "crash-1"},
      "status": {"containerStatuses": [{"name": "app", "restartCount": 5, "state": {"waiting": {"reason": "CrashLoopBackOff"}}, "lastState": {"terminated": {"exitCode": 137, "reason": "OOMKilled"}}}]}
    },
    {
      "metadata": {"name": "healthy"},
      "status": {"containerStatuses": [{"name": "app", "ready": true, "restartCount": 0, "state": {"running": {}}}]}
    }
  ]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/container_crash_detection"

  severity=$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$severity" "critical"

  affected=$(jq -c '.evidence.affected' "$SCRIPT_OUTPUT_FILE")
  assert_contains "$affected" "crash-1"

  oom_count=$(jq -r '.evidence.details.counts.oom_killed' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$oom_count" "1"

  crash_pod=$(jq -r '.evidence.details.crash_loop_back_off[0].pod' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$crash_pod" "crash-1"

  exit_code=$(jq -r '.evidence.details.crash_loop_back_off[0].exit_code' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$exit_code" "137"

  exit_meaning=$(jq -r '.evidence.details.crash_loop_back_off[0].exit_code_meaning' "$SCRIPT_OUTPUT_FILE")
  assert_contains "$exit_meaning" "OOMKilled"

  # Suggested actions should not be empty
  actions_count=$(jq -r '.evidence.suggested_actions | length' "$SCRIPT_OUTPUT_FILE")
  [ "$actions_count" -gt 0 ]
}

@test "scope/container_crash_detection: summary highlights OOM count when present" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "oom-pod"},
    "status": {"containerStatuses": [{"name": "app", "restartCount": 1, "state": {"waiting": {"reason": "CrashLoopBackOff"}}, "lastState": {"terminated": {"exitCode": 137, "reason": "OOMKilled"}}}]}
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/container_crash_detection"

  summary=$(jq -r '.evidence.summary' "$SCRIPT_OUTPUT_FILE")
  assert_contains "$summary" "OOMKilled"
}

@test "scope/container_crash_detection: skipped evidence follows schema with info severity" {
  echo '{"items":[]}' > "$PODS_FILE"

  source "$BATS_TEST_DIRNAME/../../scope/container_crash_detection"

  status=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$status" "skipped"

  severity=$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$severity" "info"

  summary=$(jq -r '.evidence.summary' "$SCRIPT_OUTPUT_FILE")
  assert_contains "$summary" "skipped"
}
