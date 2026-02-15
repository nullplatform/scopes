#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/networking/ingress_controller_sync
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
@test "networking/ingress_controller_sync: success with SuccessfullyReconciled event and ALB address" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {
      "rules": [{"host": "app.example.com"}]
    },
    "status": {
      "loadBalancer": {
        "ingress": [{"hostname": "my-alb.us-east-1.elb.amazonaws.com"}]
      }
    }
  }]
}
EOF
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Normal",
    "reason": "SuccessfullyReconciled",
    "message": "Successfully reconciled",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "successfully built model for my-ingress" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Successfully reconciled at 2024-01-01T00:00:00Z"
  assert_contains "$stripped" "ALB address assigned: my-alb.us-east-1.elb.amazonaws.com"
}

@test "networking/ingress_controller_sync: updates check result to success" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": [{"host": "app.example.com"}]},
    "status": {"loadBalancer": {"ingress": [{"hostname": "my-alb.us-east-1.elb.amazonaws.com"}]}}
  }]
}
EOF
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Normal",
    "reason": "SuccessfullyReconciled",
    "message": "Successfully reconciled",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "successfully built model for my-ingress" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"

  source "$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "networking/ingress_controller_sync: warns when no ALB controller pods found" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": [{"host": "app.example.com"}]},
    "status": {"loadBalancer": {"ingress": [{"hostname": "my-alb.us-east-1.elb.amazonaws.com"}]}}
  }]
}
EOF
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Normal",
    "reason": "SuccessfullyReconciled",
    "message": "Successfully reconciled",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF
  echo '{"items": []}' > "$ALB_CONTROLLER_PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "ALB controller pods not found in namespace kube-system"
}

@test "networking/ingress_controller_sync: reports error events" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": [{"host": "app.example.com"}]},
    "status": {"loadBalancer": {"ingress": [{"hostname": "my-alb.us-east-1.elb.amazonaws.com"}]}}
  }]
}
EOF
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Warning",
    "reason": "FailedDeployModel",
    "message": "Failed to deploy model",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Found error/warning events:"
}

@test "networking/ingress_controller_sync: warns when no events found for ingress" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": [{"host": "app.example.com"}]},
    "status": {"loadBalancer": {"ingress": [{"hostname": "my-alb.us-east-1.elb.amazonaws.com"}]}}
  }]
}
EOF
  echo '{"items":[]}' > "$EVENTS_FILE"
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "No events found for this ingress"
}

@test "networking/ingress_controller_sync: error when ALB address not assigned" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": [{"host": "app.example.com"}]},
    "status": {}
  }]
}
EOF
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Normal",
    "reason": "SuccessfullyReconciled",
    "message": "Successfully reconciled",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "ALB address not assigned yet (sync may be in progress or failing)"
}

@test "networking/ingress_controller_sync: detects errors in controller logs" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": [{"host": "app.example.com"}]},
    "status": {"loadBalancer": {"ingress": [{"hostname": "my-alb.us-east-1.elb.amazonaws.com"}]}}
  }]
}
EOF
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Normal",
    "reason": "SuccessfullyReconciled",
    "message": "Successfully reconciled",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo 'level=error msg="failed to reconcile my-ingress"' > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Found errors in ALB controller logs"
}

@test "networking/ingress_controller_sync: updates check result to failed on issues" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": [{"host": "app.example.com"}]},
    "status": {}
  }]
}
EOF
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Normal",
    "reason": "SuccessfullyReconciled",
    "message": "Successfully reconciled",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "controller-pod"}}]}
EOF
  echo "normal log" > "$ALB_CONTROLLER_LOGS_DIR/controller-pod.log"

  source "$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "networking/ingress_controller_sync: skips when no ingresses" {
  echo '{"items":[]}' > "$INGRESSES_FILE"
  echo '{"items":[]}' > "$EVENTS_FILE"
  echo '{"items":[]}' > "$ALB_CONTROLLER_PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

@test "networking/ingress_controller_sync: shows controller pod names" {
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-ingress"},
    "spec": {"rules": [{"host": "app.example.com"}]},
    "status": {"loadBalancer": {"ingress": [{"hostname": "my-alb.us-east-1.elb.amazonaws.com"}]}}
  }]
}
EOF
  cat > "$EVENTS_FILE" << 'EOF'
{
  "items": [{
    "involvedObject": {"name": "my-ingress", "kind": "Ingress"},
    "type": "Normal",
    "reason": "SuccessfullyReconciled",
    "message": "Successfully reconciled",
    "lastTimestamp": "2024-01-01T00:00:00Z"
  }]
}
EOF
  cat > "$ALB_CONTROLLER_PODS_FILE" << 'EOF'
{"items": [{"metadata": {"name": "aws-load-balancer-controller-abc123"}}]}
EOF
  echo "successfully built model for my-ingress" > "$ALB_CONTROLLER_LOGS_DIR/aws-load-balancer-controller-abc123.log"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../networking/ingress_controller_sync'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Found ALB controller pod(s): aws-load-balancer-controller-abc123"
}
