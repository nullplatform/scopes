#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/pod_readiness - pod readiness verification
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  # Setup required environment
  export NAMESPACE="test-ns"
  export LABEL_SELECTOR="app=test"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  # Create pods file
  export PODS_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$PODS_FILE"
}

# =============================================================================
# Success Tests - All Pods Ready
# =============================================================================
@test "scope/pod_readiness: success when all pods running and ready" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "conditions": [{"type": "Ready", "status": "True"}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_readiness'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Running and Ready"
  assert_contains "$output" "All pods ready"
}

@test "scope/pod_readiness: success with Succeeded pods (jobs)" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "job-pod"},
    "status": {
      "phase": "Succeeded",
      "conditions": [{"type": "Ready", "status": "False"}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_readiness'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Completed successfully"
}

# =============================================================================
# Warning Tests - Deployment In Progress
# =============================================================================
@test "scope/pod_readiness: warning when pods terminating (rollout)" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "deletionTimestamp": "2024-01-01T00:00:00Z"},
    "status": {
      "phase": "Running",
      "conditions": [{"type": "Ready", "status": "True"}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_readiness'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Terminating"
  assert_contains "$output" "rollout in progress"
}

@test "scope/pod_readiness: warning when pods starting up (ContainerCreating)" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "conditions": [{"type": "Ready", "status": "False"}],
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"waiting": {"reason": "ContainerCreating"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_readiness'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Starting up"
  assert_contains "$output" "ContainerCreating"
}

@test "scope/pod_readiness: warning when init containers running" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "conditions": [{"type": "Ready", "status": "False"}],
      "initContainerStatuses": [{
        "name": "init",
        "state": {"running": {}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_readiness'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Init:"
}

# =============================================================================
# Failure Tests - Pods Not Ready
# =============================================================================
@test "scope/pod_readiness: fails when pods not ready without valid reason" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "conditions": [{"type": "Ready", "status": "False", "reason": "ContainersNotReady"}],
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "restartCount": 0,
        "state": {"running": {}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_readiness'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Pods not ready"
}

@test "scope/pod_readiness: shows container status details" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "conditions": [{"type": "Ready", "status": "False"}],
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "restartCount": 5,
        "state": {"running": {}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_readiness'"

  assert_contains "$output" "Container Status"
  assert_contains "$output" "app:"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "scope/pod_readiness: skips when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/pod_readiness'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

# =============================================================================
# Evidence Tests
# =============================================================================
@test "scope/pod_readiness: includes ready count in evidence" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "conditions": [{"type": "Ready", "status": "True"}]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/pod_readiness"

  ready=$(jq -r '.evidence.ready' "$SCRIPT_OUTPUT_FILE")
  total=$(jq -r '.evidence.total' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$ready" "1"
  assert_equal "$total" "1"
}
