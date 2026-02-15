#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/networking/alb_capacity_check
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
  export EVENTS_FILE="$(mktemp)"
  export ALB_CONTROLLER_PODS_FILE="$(mktemp)"
  export ALB_CONTROLLER_LOGS_DIR="$(mktemp -d)"
  export ALB_CONTROLLER_NAMESPACE="kube-system"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$INGRESSES_FILE"
  rm -f "$EVENTS_FILE"
  rm -f "$ALB_CONTROLLER_PODS_FILE"
  rm -rf "$ALB_CONTROLLER_LOGS_DIR"
}

# =============================================================================
# Success Tests
# =============================================================================
@test "networking/alb_capacity_check: success when no issues found" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/scheme": "internet-facing",
        "alb.ingress.kubernetes.io/subnets": "subnet-1"
      }
    },
    "spec": {
      "rules": [{"host": "app.example.com", "http": {"paths": [{"path": "/", "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}}]}}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No IP exhaustion issues detected"
  assert_contains "$stripped" "No critical ALB capacity or configuration issues detected"
}

@test "networking/alb_capacity_check: updates check result to success when no issues" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/scheme": "internet-facing",
        "alb.ingress.kubernetes.io/subnets": "subnet-1"
      }
    },
    "spec": {
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  source "$BATS_TEST_DIRNAME/../../networking/alb_capacity_check"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "networking/alb_capacity_check: detects IP exhaustion in controller logs" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
      }
    },
    "spec": {
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "ERROR no available ip addresses in subnet" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "ALB subnet IP exhaustion detected"
}

@test "networking/alb_capacity_check: detects certificate errors in controller logs" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/certificate-arn": "arn:aws:acm:us-east-1:123456:certificate/abc",
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
      }
    },
    "spec": {
      "tls": [{"hosts": ["app.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "my-ingress certificate not found error" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Certificate validation errors found"
}

@test "networking/alb_capacity_check: detects host in rules but not in TLS" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/certificate-arn": "arn:aws:acm:us-east-1:123456:certificate/abc",
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
      }
    },
    "spec": {
      "tls": [{"hosts": ["other.example.com"]}],
      "rules": [
        {"host": "app.example.com", "http": {"paths": [{"path": "/", "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}}]}},
        {"host": "other.example.com", "http": {"paths": [{"path": "/", "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}}]}}
      ]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Host 'app.example.com' in rules but not in TLS configuration"
}

@test "networking/alb_capacity_check: warns when TLS hosts but no certificate ARN" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
      }
    },
    "spec": {
      "tls": [{"hosts": ["app.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "TLS hosts configured but no ACM certificate ARN annotation"
}

@test "networking/alb_capacity_check: warns when no scheme annotation" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {}
    },
    "spec": {
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No scheme annotation (defaulting to internal)"
}

@test "networking/alb_capacity_check: detects subnet error events" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
      }
    },
    "spec": {
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Warning",
    "reason": "FailedDeployModel",
    "message": "Failed to find subnet in availability zone us-east-1a",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Subnet configuration issues"
}

@test "networking/alb_capacity_check: updates check result to failed on issues" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
      }
    },
    "spec": {
      "tls": [{"hosts": ["other.example.com"]}],
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  source "$BATS_TEST_DIRNAME/../../networking/alb_capacity_check"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "networking/alb_capacity_check: skips when no ingresses" {
  echo '{"items":[]}' > "$INGRESSES_FILE"
  echo '{"items":[]}' > "$ALB_CONTROLLER_PODS_FILE"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

@test "networking/alb_capacity_check: reports no SSL/TLS when not configured" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
      }
    },
    "spec": {
      "rules": [{"host": "app.example.com", "http": {"paths": [{"path": "/", "backend": {"service": {"name": "my-svc", "port": {"number": 80}}}}]}}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No SSL/TLS configured (HTTP only)"
}

@test "networking/alb_capacity_check: shows auto-discovered subnets info when no subnet annotation" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {
      "name": "my-ingress",
      "annotations": {
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
      }
    },
    "spec": {
      "rules": [{"host": "app.example.com"}]
    }
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log line" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"
  echo '{"items":[]}' > "$EVENTS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/alb_capacity_check'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Using auto-discovered subnets"
}
