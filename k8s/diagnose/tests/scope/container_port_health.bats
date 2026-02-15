#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/container_port_health
# =============================================================================

strip_ansi() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

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
@test "scope/container_port_health: success when ports are listening" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "
    timeout() { shift; \"\$@\"; }
    export -f timeout
    nc() { return 0; }
    export -f nc
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Checking pod pod-1:"
  assert_contains "$stripped" "Listening"
  assert_contains "$stripped" "Port connectivity verified on 1 container(s)"
}

@test "scope/container_port_health: success with multiple ports listening" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}, {"containerPort": 9090}]
      }]
    }
  }]
}
EOF

  run bash -c "
    timeout() { shift; \"\$@\"; }
    export -f timeout
    nc() { return 0; }
    export -f nc
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Port 8080:"
  assert_contains "$stripped" "Port 9090:"
  assert_contains "$stripped" "Port connectivity verified on 1 container(s)"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "scope/container_port_health: failed when port not listening" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "
    timeout() { shift; \"\$@\"; }
    export -f timeout
    nc() { return 1; }
    export -f nc
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Port 8080:"
  assert_contains "$stripped" "Declared but not listening or unreachable"
  assert_contains "$stripped" "Check application configuration and ensure it listens on port 8080"
}

@test "scope/container_port_health: updates status to failed when port not listening" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "
    timeout() { shift; \"\$@\"; }
    export -f timeout
    nc() { return 1; }
    export -f nc
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'
  "

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"

  tested=$(jq -r '.evidence.tested' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$tested" "1"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "scope/container_port_health: skips when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

@test "scope/container_port_health: skips pod not running" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"waiting": {"reason": "ContainerCreating"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: Not running (phase: Pending), skipping port checks"
}

@test "scope/container_port_health: skips container in CrashLoopBackOff" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"waiting": {"reason": "CrashLoopBackOff", "message": "back-off 5m0s restarting"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Cannot test ports - container is in error state: CrashLoopBackOff"
  assert_contains "$stripped" "Message: back-off 5m0s restarting"
  assert_contains "$stripped" "Fix container startup issues (check container_crash_detection results)"
}

@test "scope/container_port_health: skips container terminated" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"terminated": {"exitCode": 1, "reason": "Error"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Cannot test ports - container terminated (Exit: 1, Reason: Error)"
  assert_contains "$stripped" "Fix container termination (check container_crash_detection results)"
}

@test "scope/container_port_health: skips container in ContainerCreating" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"waiting": {"reason": "ContainerCreating"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Container is starting (ContainerCreating) - skipping port checks"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "scope/container_port_health: warns when running but not ready" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "
    timeout() { shift; \"\$@\"; }
    export -f timeout
    nc() { return 0; }
    export -f nc
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Container is running but not ready - port connectivity may fail"
}

@test "scope/container_port_health: no ports declared" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app"
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Container 'app': No ports declared"
}

@test "scope/container_port_health: all containers skipped sets status skipped" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"waiting": {"reason": "CrashLoopBackOff"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/container_port_health"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "skipped"

  skipped=$(jq -r '.evidence.skipped' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$skipped" "1"
}

@test "scope/container_port_health: pod with no IP skips port checks" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": null,
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/container_port_health'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: No IP assigned, skipping port checks"
}

@test "scope/container_port_health: updates status to success when ports healthy" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "podIP": "10.0.0.1",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  timeout() { shift; "$@"; }
  export -f timeout
  nc() { return 0; }
  export -f nc

  source "$BATS_TEST_DIRNAME/../../scope/container_port_health"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"

  tested=$(jq -r '.evidence.tested' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$tested" "1"

  unset -f nc timeout
}
