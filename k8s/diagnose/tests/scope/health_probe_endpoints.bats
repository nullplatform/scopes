#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/health_probe_endpoints
# =============================================================================

strip_ansi() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Find bash 4+ (required for ${var,,} syntax used in the source script)
find_modern_bash() {
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash; do
    if [[ -x "$candidate" ]]; then
      local ver
      ver=$("$candidate" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null) || true
      if [[ "$ver" -ge 4 ]] 2>/dev/null; then
        echo "$candidate"
        return 0
      fi
    fi
  done
  echo ""
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

  MODERN_BASH=$(find_modern_bash)
  export MODERN_BASH
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
@test "scope/health_probe_endpoints: success when readiness probe returns 200" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '200'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Checking pod pod-1:"
  assert_contains "$stripped" "Readiness Probe on HTTP://8080/health:"
  assert_contains "$stripped" "HTTP 200"
  assert_contains "$stripped" "Health probes verified on 1 container(s)"
}

@test "scope/health_probe_endpoints: success with liveness and readiness probes" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "readinessProbe": {
          "httpGet": {"path": "/ready", "port": 8080, "scheme": "HTTP"}
        },
        "livenessProbe": {
          "httpGet": {"path": "/alive", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '200'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Readiness Probe on HTTP://8080/ready:"
  assert_contains "$stripped" "Liveness Probe on HTTP://8080/alive:"
  assert_contains "$stripped" "Health probes verified on 1 container(s)"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "scope/health_probe_endpoints: failed when readiness probe returns 404" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '404'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Readiness Probe on HTTP://8080/health:"
  assert_contains "$stripped" "HTTP 404 - Health check endpoint not found"
  assert_contains "$stripped" "Update probe path or implement the endpoint in application"
}

@test "scope/health_probe_endpoints: updates status to failed on 404" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '404'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

@test "scope/health_probe_endpoints: warning when probe returns 500" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '500'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Readiness Probe on HTTP://8080/health:"
  assert_contains "$stripped" "HTTP 500 - Application error"
  assert_contains "$stripped" "Check application logs and fix internal errors or dependencies"
}

@test "scope/health_probe_endpoints: updates status to warning on 500" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '500'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "warning"
}

# =============================================================================
# Probe Type Tests
# =============================================================================
@test "scope/health_probe_endpoints: tcp socket probe shows info message" {
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
        "readinessProbe": {
          "tcpSocket": {"port": 8080}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Readiness Probe: TCP Socket on port 8080 (tested in port health check)"
}

@test "scope/health_probe_endpoints: exec probe shows cannot test directly" {
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
        "readinessProbe": {
          "exec": {"command": ["cat", "/tmp/healthy"]}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Readiness Probe: Exec [cat /tmp/healthy] (cannot test directly)"
}

# =============================================================================
# Warning Tests
# =============================================================================
@test "scope/health_probe_endpoints: warns when no probes configured" {
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

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No health probes configured (recommend adding readiness/liveness probes)"
}

@test "scope/health_probe_endpoints: container not ready shows info" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '200'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Container is running but not ready - probe checks may show why"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "scope/health_probe_endpoints: skips when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

@test "scope/health_probe_endpoints: skips container not running (CrashLoopBackOff)" {
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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Cannot test probes - container is in error state: CrashLoopBackOff"
  assert_contains "$stripped" "Fix container startup issues (check container_crash_detection results)"
}

@test "scope/health_probe_endpoints: skips container terminated" {
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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Cannot test probes - container terminated (Exit: 1, Reason: Error)"
  assert_contains "$stripped" "Fix container termination (check container_crash_detection results)"
}

@test "scope/health_probe_endpoints: all containers skipped sets status skipped" {
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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "skipped"

  skipped=$(jq -r '.evidence.skipped' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$skipped" "1"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "scope/health_probe_endpoints: pod with no IP skips probe checks" {
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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: No IP assigned, skipping probe checks"
}

@test "scope/health_probe_endpoints: pod not running skips probe checks" {
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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: Not running (phase: Pending), skipping probe checks"
}

@test "scope/health_probe_endpoints: updates status to success when probes healthy" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "readinessProbe": {
          "httpGet": {"path": "/health", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '200'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"

  tested=$(jq -r '.evidence.tested' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$tested" "1"
}

@test "scope/health_probe_endpoints: startup probe with httpGet returns 200" {
  [[ -n "$MODERN_BASH" ]] || skip "bash 4+ required for \${var,,} syntax"

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
        "startupProbe": {
          "httpGet": {"path": "/startup", "port": 8080, "scheme": "HTTP"}
        },
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run "$MODERN_BASH" -c "
    curl() { echo '200'; return 0; }
    export -f curl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/health_probe_endpoints'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Startup Probe on HTTP://8080/startup:"
  assert_contains "$stripped" "HTTP 200"
}
