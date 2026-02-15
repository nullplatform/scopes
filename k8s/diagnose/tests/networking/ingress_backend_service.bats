#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/networking/ingress_backend_service
# =============================================================================

strip_ansi() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export SCOPE_LABEL_SELECTOR="scope_id=123"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"
  export SCRIPT_LOG_FILE="$(mktemp)"
  export INGRESSES_FILE="$(mktemp)"
  export SERVICES_FILE="$(mktemp)"
  export ENDPOINTS_FILE="$(mktemp)"
  export PODS_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$INGRESSES_FILE"
  rm -f "$SERVICES_FILE"
  rm -f "$ENDPOINTS_FILE"
  rm -f "$PODS_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "networking/ingress_backend_service: success with backend service having ready endpoints" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}
          }]
        }
      }]
    }
  }]
}
EOF
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "selector": {"app": "test"},
      "ports": [{"port": 80, "targetPort": 8080}]
    }
  }]
}
EOF
  cat > "$ENDPOINTS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "subsets": [{
      "addresses": [{"ip": "10.0.0.1", "targetRef": {"name": "pod-1"}}],
      "ports": [{"port": 8080}]
    }]
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Backend: my-svc:80 (1 ready endpoint(s))"
  assert_contains "$stripped" "All backend services healthy"
}

@test "networking/ingress_backend_service: updates check result to success" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}
          }]
        }
      }]
    }
  }]
}
EOF
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "test"}, "ports": [{"port": 80, "targetPort": 8080}]}
  }]
}
EOF
  cat > "$ENDPOINTS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "subsets": [{"addresses": [{"ip": "10.0.0.1", "targetRef": {"name": "pod-1"}}], "ports": [{"port": 8080}]}]
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "networking/ingress_backend_service: error when default backend service not found" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "defaultBackend": {"service": {"name": "missing-svc", "port": {"number": 80}}},
      "rules": []
    }
  }]
}
EOF
  echo '{"items":[]}' > "$SERVICES_FILE"
  echo '{"items":[]}' > "$ENDPOINTS_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Default backend: Service 'missing-svc' not found"
}

@test "networking/ingress_backend_service: error when default backend has no endpoints" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "defaultBackend": {"service": {"name": "my-svc", "port": {"number": 80}}},
      "rules": []
    }
  }]
}
EOF
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "test"}, "ports": [{"port": 80, "targetPort": 8080}]}
  }]
}
EOF
  cat > "$ENDPOINTS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "subsets": []
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Default backend: my-svc:80 (no endpoints)"
}

@test "networking/ingress_backend_service: warns about not-ready endpoints alongside ready ones" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}
          }]
        }
      }]
    }
  }]
}
EOF
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "test"}, "ports": [{"port": 80, "targetPort": 8080}]}
  }]
}
EOF
  cat > "$ENDPOINTS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "subsets": [{
      "addresses": [{"ip": "10.0.0.1", "targetRef": {"name": "pod-1"}}],
      "notReadyAddresses": [{"ip": "10.0.0.2", "targetRef": {"name": "pod-2"}}],
      "ports": [{"port": 8080}]
    }]
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Backend: my-svc:80 (1 ready endpoint(s))"
  assert_contains "$stripped" "Also has 1 not ready endpoint(s)"
}

@test "networking/ingress_backend_service: handles service with multiple ports" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}
          }]
        }
      }]
    }
  }]
}
EOF
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "test"}, "ports": [{"port": 80, "targetPort": 8080}, {"port": 443, "targetPort": 8443}]}
  }]
}
EOF
  cat > "$ENDPOINTS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "subsets": [{"addresses": [{"ip": "10.0.0.1", "targetRef": {"name": "pod-1"}}], "ports": [{"port": 8080}]}]
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Backend: my-svc:80 (1 ready endpoint(s))"
  assert_contains "$stripped" "All backend services healthy"
}

@test "networking/ingress_backend_service: error when port not found in service" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "backend": {"service": {"name": "my-svc", "port": {"number": 9090}}}
          }]
        }
      }]
    }
  }]
}
EOF
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "test"}, "ports": [{"port": 80, "targetPort": 8080}]}
  }]
}
EOF
  cat > "$ENDPOINTS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "subsets": [{"addresses": [{"ip": "10.0.0.1", "targetRef": {"name": "pod-1"}}], "ports": [{"port": 8080}]}]
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Backend: Port 9090 not found in service my-svc"
}

@test "networking/ingress_backend_service: error when backend service not found in namespace" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "backend": {"service": {"name": "missing-svc", "port": {"number": 80}}}
          }]
        }
      }]
    }
  }]
}
EOF
  echo '{"items":[]}' > "$SERVICES_FILE"
  echo '{"items":[]}' > "$ENDPOINTS_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Service 'missing-svc' not found in namespace"
}

@test "networking/ingress_backend_service: warns when no path rules defined" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com"
      }]
    }
  }]
}
EOF
  echo '{"items":[]}' > "$SERVICES_FILE"
  echo '{"items":[]}' > "$ENDPOINTS_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No path rules defined"
}

@test "networking/ingress_backend_service: updates check result to failed on issues" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "backend": {"service": {"name": "missing-svc", "port": {"number": 80}}}
          }]
        }
      }]
    }
  }]
}
EOF
  echo '{"items":[]}' > "$SERVICES_FILE"
  echo '{"items":[]}' > "$ENDPOINTS_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "networking/ingress_backend_service: skips when no ingresses" {
  echo '{"items":[]}' > "$INGRESSES_FILE"
  echo '{"items":[]}' > "$SERVICES_FILE"
  echo '{"items":[]}' > "$ENDPOINTS_FILE"
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

@test "networking/ingress_backend_service: shows endpoint details with pod name and IP" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "app.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}
          }]
        }
      }]
    }
  }]
}
EOF
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"selector": {"app": "test"}, "ports": [{"port": 80, "targetPort": 8080}]}
  }]
}
EOF
  cat > "$ENDPOINTS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "subsets": [{
      "addresses": [
        {"ip": "10.0.0.1", "targetRef": {"name": "pod-1"}},
        {"ip": "10.0.0.2", "targetRef": {"name": "pod-2"}}
      ],
      "ports": [{"port": 8080}]
    }]
  }]
}
EOF
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_backend_service'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "pod-1 -> 10.0.0.1:8080"
  assert_contains "$stripped" "pod-2 -> 10.0.0.2:8080"
}
