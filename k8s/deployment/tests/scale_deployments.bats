#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/scale_deployments - scale blue/green deployments
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Set required environment variables
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-new"
  export DEPLOY_STRATEGY="rolling"
  export DEPLOYMENT_MAX_WAIT_IN_SECONDS=60

  # Base CONTEXT with required fields
  export CONTEXT='{
    "scope": {
      "id": "scope-123",
      "current_active_deployment": "deploy-old"
    },
    "green_replicas": "5",
    "blue_replicas": "3"
  }'

  # Track kubectl calls
  export KUBECTL_CALLS=""

  # Mock kubectl
  kubectl() {
    KUBECTL_CALLS="$KUBECTL_CALLS|$*"
    return 0
  }
  export -f kubectl

  # Mock wait_blue_deployment_active
  export NP_OUTPUT_DIR="$(mktemp -d)"
  mkdir -p "$SERVICE_PATH/deployment"

  # Create a mock wait_blue_deployment_active that captures env vars before they're unset
  cat > "$NP_OUTPUT_DIR/wait_blue_deployment_active" << 'EOF'
#!/bin/bash
echo "Mock: wait_blue_deployment_active called"
# Capture the values to global variables so they persist after unset
CAPTURED_TIMEOUT="$TIMEOUT"
CAPTURED_SKIP_DEPLOYMENT_STATUS_CHECK="$SKIP_DEPLOYMENT_STATUS_CHECK"
export CAPTURED_TIMEOUT CAPTURED_SKIP_DEPLOYMENT_STATUS_CHECK
EOF
  chmod +x "$NP_OUTPUT_DIR/wait_blue_deployment_active"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  unset KUBECTL_CALLS
  unset -f kubectl
}

# Helper to run scale_deployments with mocked wait
run_scale_deployments() {
  # Override the sourced script path
  local script_content=$(cat "$PROJECT_ROOT/k8s/deployment/scale_deployments")
  # Replace the source line with our mock
  script_content=$(echo "$script_content" | sed "s|source \"\$SERVICE_PATH/deployment/wait_blue_deployment_active\"|source \"$NP_OUTPUT_DIR/wait_blue_deployment_active\"|")

  eval "$script_content"
}

# =============================================================================
# Strategy Detection Tests
# =============================================================================
@test "scale_deployments: only runs for rolling strategy" {
  export DEPLOY_STRATEGY="rolling"

  run_scale_deployments

  assert_contains "$KUBECTL_CALLS" "scale deployment"
}

@test "scale_deployments: skips scaling for blue-green strategy" {
  export DEPLOY_STRATEGY="blue-green"
  export KUBECTL_CALLS=""

  run_scale_deployments

  # Should not contain scale commands
  [[ "$KUBECTL_CALLS" != *"scale deployment"* ]]
}

@test "scale_deployments: skips scaling for unknown strategy" {
  export DEPLOY_STRATEGY="unknown"
  export KUBECTL_CALLS=""

  run_scale_deployments

  [[ "$KUBECTL_CALLS" != *"scale deployment"* ]]
}

# =============================================================================
# Green Deployment Scaling Tests
# =============================================================================
@test "scale_deployments: scales green deployment to green_replicas" {
  run_scale_deployments

  assert_contains "$KUBECTL_CALLS" "scale deployment d-scope-123-deploy-new"
  assert_contains "$KUBECTL_CALLS" "--replicas=5"
}

@test "scale_deployments: constructs correct green deployment name" {
  run_scale_deployments

  assert_contains "$KUBECTL_CALLS" "d-scope-123-deploy-new"
}

# =============================================================================
# Blue Deployment Scaling Tests
# =============================================================================
@test "scale_deployments: scales blue deployment to blue_replicas" {
  run_scale_deployments

  assert_contains "$KUBECTL_CALLS" "scale deployment d-scope-123-deploy-old"
  assert_contains "$KUBECTL_CALLS" "--replicas=3"
}

@test "scale_deployments: constructs correct blue deployment name" {
  run_scale_deployments

  assert_contains "$KUBECTL_CALLS" "d-scope-123-deploy-old"
}

# =============================================================================
# Green and Blue Scaling Tests
# =============================================================================
@test "scale_deployments: scales green and blue with correct commands" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.green_replicas = "7" | .blue_replicas = "2" | .scope.current_active_deployment = "deploy-active-123"')
  export K8S_NAMESPACE="custom-namespace"

  run_scale_deployments

  assert_contains "$KUBECTL_CALLS" "scale deployment d-scope-123-deploy-new -n custom-namespace --replicas=7"

  assert_contains "$KUBECTL_CALLS" "scale deployment d-scope-123-deploy-active-123 -n custom-namespace --replicas=2"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "scale_deployments: fails when green deployment scale fails" {
  kubectl() {
    if [[ "$*" == *"deploy-new"* ]]; then
      return 1  # Fail for green deployment
    fi
    return 0
  }
  export -f kubectl

  run bash -c "source '$PROJECT_ROOT/testing/assertions.sh'; \
    export SERVICE_PATH='$SERVICE_PATH' K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' \
    DEPLOYMENT_ID='$DEPLOYMENT_ID' DEPLOY_STRATEGY='$DEPLOY_STRATEGY' CONTEXT='$CONTEXT'; \
    source '$PROJECT_ROOT/k8s/deployment/scale_deployments'"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to scale green deployment"
}

@test "scale_deployments: fails when blue deployment scale fails" {
  kubectl() {
    if [[ "$*" == *"deploy-old"* ]]; then
      return 1  # Fail for blue deployment
    fi
    return 0
  }
  export -f kubectl

  run bash -c "source '$PROJECT_ROOT/testing/assertions.sh'; \
    export SERVICE_PATH='$SERVICE_PATH' K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' \
    DEPLOYMENT_ID='$DEPLOYMENT_ID' DEPLOY_STRATEGY='$DEPLOY_STRATEGY' CONTEXT='$CONTEXT'; \
    source '$PROJECT_ROOT/k8s/deployment/scale_deployments'"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to scale blue deployment"
}

# =============================================================================
# Wait Configuration Tests
# =============================================================================
@test "scale_deployments: sets TIMEOUT from DEPLOYMENT_MAX_WAIT_IN_SECONDS" {
  export DEPLOYMENT_MAX_WAIT_IN_SECONDS=120

  run_scale_deployments

  assert_equal "$CAPTURED_TIMEOUT" "120"
}

@test "scale_deployments: defaults TIMEOUT to 600 seconds" {
  unset DEPLOYMENT_MAX_WAIT_IN_SECONDS

  run_scale_deployments

  assert_equal "$CAPTURED_TIMEOUT" "600"
}

@test "scale_deployments: sets SKIP_DEPLOYMENT_STATUS_CHECK=true" {
  run_scale_deployments

  assert_equal "$CAPTURED_SKIP_DEPLOYMENT_STATUS_CHECK" "true"
}

# =============================================================================
# Cleanup Tests
# =============================================================================
@test "scale_deployments: unsets TIMEOUT after wait" {
  run_scale_deployments

  # After the script runs, TIMEOUT should be unset
  [ -z "$TIMEOUT" ]
}

@test "scale_deployments: unsets SKIP_DEPLOYMENT_STATUS_CHECK after wait" {
  run_scale_deployments

  [ -z "$SKIP_DEPLOYMENT_STATUS_CHECK" ]
}

# =============================================================================
# Order of Operations Tests
# =============================================================================
@test "scale_deployments: scales green before blue" {
  run_scale_deployments

  # Find positions of scale commands
  local green_pos=$(echo "$KUBECTL_CALLS" | grep -o ".*deploy-new" | wc -c)
  local blue_pos=$(echo "$KUBECTL_CALLS" | grep -o ".*deploy-old" | wc -c)

  # Green should appear first
  [ "$green_pos" -lt "$blue_pos" ]
}
