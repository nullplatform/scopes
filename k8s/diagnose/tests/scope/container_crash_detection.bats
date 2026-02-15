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
