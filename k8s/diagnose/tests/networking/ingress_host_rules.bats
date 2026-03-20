#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/networking/ingress_host_rules
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export SCOPE_LABEL_SELECTOR="scope_id=123"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  export INGRESSES_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$INGRESSES_FILE"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "networking/ingress_host_rules: success with valid host and path" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "api.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "pathType": "Prefix",
            "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}
          }]
        }
      }]
    },
    "status": {
      "loadBalancer": {"ingress": [{"hostname": "lb.example.com"}]}
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Host: api.example.com"
  assert_contains "$output" "Path: /"
}

@test "networking/ingress_host_rules: shows ingress address" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "api.example.com",
        "http": {"paths": [{"path": "/", "pathType": "Prefix", "backend": {"service": {"name": "svc", "port": {"number": 80}}}}]}
      }]
    },
    "status": {
      "loadBalancer": {"ingress": [{"ip": "1.2.3.4"}]}
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  assert_contains "$output" "Ingress address: 1.2.3.4"
}

# =============================================================================
# Warning Tests
# =============================================================================
@test "networking/ingress_host_rules: warns on catch-all host" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "http": {
          "paths": [{"path": "/", "pathType": "Prefix", "backend": {"service": {"name": "svc", "port": {"number": 80}}}}]
        }
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "catch-all"
}

@test "networking/ingress_host_rules: warns when address not assigned" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "api.example.com",
        "http": {"paths": [{"path": "/", "pathType": "Prefix", "backend": {"service": {"name": "svc", "port": {"number": 80}}}}]}
      }]
    },
    "status": {}
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  assert_contains "$output" "not yet assigned"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "networking/ingress_host_rules: fails when no rules and no default backend" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": []}
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "No rules and no default backend"
}

@test "networking/ingress_host_rules: fails on invalid pathType" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "api.example.com",
        "http": {
          "paths": [{
            "path": "/api",
            "pathType": "InvalidType",
            "backend": {"service": {"name": "svc", "port": {"number": 80}}}
          }]
        }
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Invalid pathType"
}

@test "networking/ingress_host_rules: fails when no paths defined" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{
        "host": "api.example.com",
        "http": {"paths": []}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "No paths defined"
}

# =============================================================================
# Default Backend Tests
# =============================================================================
@test "networking/ingress_host_rules: success with default backend only" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "defaultBackend": {"service": {"name": "default-svc", "port": {"number": 80}}},
      "rules": []
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Catch-all rule"
  assert_contains "$output" "default-svc"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "networking/ingress_host_rules: skips when no ingresses" {
  echo '{"items":[]}' > "$INGRESSES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_host_rules'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}
