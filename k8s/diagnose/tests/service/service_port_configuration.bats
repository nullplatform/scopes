#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/service/service_port_configuration
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export LABEL_SELECTOR="app=test"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"
  export SCRIPT_LOG_FILE="$(mktemp)"
  export SERVICES_FILE="$(mktemp)"
  export PODS_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$SERVICES_FILE"
  rm -f "$PODS_FILE"
}

strip_ansi() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# =============================================================================
# Success Tests
# =============================================================================
@test "service/service_port_configuration: success when numeric targetPort matches container port" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  kubectl() {
    case "$*" in
      *"exec"*) return 0 ;;
    esac
  }
  export -f kubectl

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && kubectl() { return 0; } && export -f kubectl && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Port 80 -> 8080 (http): Configuration OK [container: app]"
  assert_contains "$stripped" "Port 8080 is accepting connections"
}

@test "service/service_port_configuration: success when named targetPort resolves" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": "http", "name": "web"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && kubectl() { return 0; } && export -f kubectl && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Resolves to 8080 [container: app]"
}

@test "service/service_port_configuration: updates status to success when all ports match" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  kubectl() { return 0; }
  export -f kubectl

  source "$BATS_TEST_DIRNAME/../../service/service_port_configuration"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "service/service_port_configuration: fails when container port not found" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 9090, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Container port 9090 not found"
  assert_contains "$stripped" "Available ports by container:"
}

@test "service/service_port_configuration: fails when named port not found in containers" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": "grpc", "name": "api"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Named port not found in containers"
}

@test "service/service_port_configuration: fails when port not accepting connections" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && kubectl() { return 1; } && export -f kubectl && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Port 8080 is NOT accepting connections"
}

@test "service/service_port_configuration: updates status to failed when port mismatch" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 9090, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../service/service_port_configuration"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

@test "service/service_port_configuration: updates status to failed when connectivity fails" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils'
    kubectl() { return 1; }
    export -f kubectl
    source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'
  "

  [ "$status" -eq 0 ]
  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

@test "service/service_port_configuration: shows action to update targetPort on mismatch" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 9090, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Update service targetPort to match container port or fix container port"
}

@test "service/service_port_configuration: shows action for named port not found" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": "grpc", "name": "api"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Define named port in container spec or use numeric targetPort"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "service/service_port_configuration: no ports defined" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"}
    }
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No ports defined"
}

@test "service/service_port_configuration: no selector skips port validation" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No selector, skipping port validation"
}

@test "service/service_port_configuration: no matching pods found" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "other"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No pods found to validate ports"
}

@test "service/service_port_configuration: skips when no services (require_services fails)" {
  echo '{"items":[]}' > "$SERVICES_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

@test "service/service_port_configuration: shows connectivity check info message" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && kubectl() { return 0; } && export -f kubectl && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Testing connectivity to port 8080 in container 'app'"
}

@test "service/service_port_configuration: shows log check hint when connectivity fails" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && kubectl() { return 1; } && export -f kubectl && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Check logs: kubectl logs pod-1 -n test-ns -c app"
}

@test "service/service_port_configuration: multiple ports with mixed results" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [
        {"port": 80, "targetPort": 8080, "name": "http"},
        {"port": 443, "targetPort": 9999, "name": "https"}
      ]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && kubectl() { return 0; } && export -f kubectl && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Port 80 -> 8080 (http): Configuration OK [container: app]"
  assert_contains "$stripped" "Container port 9999 not found"
}

@test "service/service_port_configuration: shows service port configuration header" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080, "name": "http"}]
    }
  }]
}
EOF
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1", "labels": {"app": "test"}},
    "spec": {
      "containers": [{
        "name": "app",
        "ports": [{"containerPort": 8080, "name": "http"}]
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && kubectl() { return 0; } && export -f kubectl && source '$BATS_TEST_DIRNAME/../../service/service_port_configuration'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Service my-svc port configuration:"
}
