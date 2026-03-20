#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/memory_limits_check
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
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$PODS_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "scope/memory_limits_check: success when no OOMKilled" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {}},
        "lastState": {}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/memory_limits_check'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "No OOMKilled"
}

@test "scope/memory_limits_check: updates check result to success" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "state": {"running": {}},
        "lastState": {}
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/memory_limits_check"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests - OOMKilled
# =============================================================================
@test "scope/memory_limits_check: detects OOMKilled containers" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{
        "name": "app",
        "resources": {
          "limits": {"memory": "256Mi"},
          "requests": {"memory": "128Mi"}
        }
      }]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"waiting": {"reason": "CrashLoopBackOff"}},
        "lastState": {"terminated": {"reason": "OOMKilled", "exitCode": 137}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/memory_limits_check'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "OOMKilled"
  assert_contains "$output" "pod-1"
}

@test "scope/memory_limits_check: shows memory limit and request" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{
        "name": "app",
        "resources": {
          "limits": {"memory": "512Mi"},
          "requests": {"memory": "256Mi"}
        }
      }]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "lastState": {"terminated": {"reason": "OOMKilled"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/memory_limits_check'"

  assert_contains "$output" "Memory Limit: 512Mi"
  assert_contains "$output" "Memory Request: 256Mi"
}

@test "scope/memory_limits_check: shows action for OOM" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{"name": "app", "resources": {}}]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "lastState": {"terminated": {"reason": "OOMKilled"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/memory_limits_check'"

  assert_contains "$output" "🔧"
  assert_contains "$output" "Increase memory limits"
}

@test "scope/memory_limits_check: shows 'not set' when no limits" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{"name": "app"}]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "lastState": {"terminated": {"reason": "OOMKilled"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/memory_limits_check'"

  assert_contains "$output" "not set"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "scope/memory_limits_check: skips when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/memory_limits_check'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

# =============================================================================
# Status Update Tests
# =============================================================================
@test "scope/memory_limits_check: updates status to failed on OOM" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {"containers": [{"name": "app"}]},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "lastState": {"terminated": {"reason": "OOMKilled"}}
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/memory_limits_check"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}
