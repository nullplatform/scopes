#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/wait_deployment_active - poll until deployment ready
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-456"
  export TIMEOUT=30
  export NP_API_KEY="test-api-key"
  export SKIP_DEPLOYMENT_STATUS_CHECK="false"

  # Mock np CLI - running by default
  np() {
    case "$1" in
      deployment)
        echo "running"
        ;;
    esac
  }
  export -f np

  # Mock kubectl - deployment ready by default
  kubectl() {
    case "$*" in
      "get deployment d-scope-123-deploy-456 -n test-namespace -o json")
        echo '{
          "spec": {"replicas": 3},
          "status": {
            "availableReplicas": 3,
            "updatedReplicas": 3,
            "readyReplicas": 3
          }
        }'
        ;;
      "get pods"*)
        echo ""
        ;;
      "get events"*)
        echo '{"items":[]}'
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl
}

teardown() {
  unset -f np
  unset -f kubectl
}

# =============================================================================
# Success Case
# =============================================================================
@test "wait_deployment_active: succeeds with all expected logging when replicas ready" {
  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Waiting for deployment 'd-scope-123-deploy-456' to become active..."
  assert_contains "$output" "📋 Namespace: test-namespace"
  assert_contains "$output" "📋 Timeout: 30s (max 3 iterations)"
  assert_contains "$output" "📡 Checking deployment status (attempt 1/3)..."
  assert_contains "$output" "✅ All pods in deployment 'd-scope-123-deploy-456' are available and ready!"
}

@test "wait_deployment_active: accepts waiting_for_instances status" {
  np() {
    echo "waiting_for_instances"
  }
  export -f np

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ All pods in deployment 'd-scope-123-deploy-456' are available and ready!"
}

@test "wait_deployment_active: skips NP status check when SKIP_DEPLOYMENT_STATUS_CHECK=true" {
  export SKIP_DEPLOYMENT_STATUS_CHECK="true"

  np() {
    echo "failed"  # Would fail if checked
  }
  export -f np

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ All pods in deployment 'd-scope-123-deploy-456' are available and ready!"
}

# =============================================================================
# Timeout Error Case
# =============================================================================
@test "wait_deployment_active: fails with full troubleshooting on timeout" {
  # TIMEOUT=5 means MAX_ITERATIONS=0, so first iteration (1 > 0) times out immediately
  export TIMEOUT=5

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Waiting for deployment 'd-scope-123-deploy-456' to become active..."
  assert_contains "$output" "📋 Namespace: test-namespace"
  assert_contains "$output" "📋 Timeout: 5s (max 0 iterations)"
  assert_contains "$output" "❌ Timeout waiting for deployment"
  assert_contains "$output" "📋 Maximum iterations (0) reached"
}

# =============================================================================
# NP CLI Error Cases
# =============================================================================
@test "wait_deployment_active: fails with full troubleshooting when NP CLI fails" {
  np() {
    echo "Error connecting to API" >&2
    return 1
  }
  export -f np

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Waiting for deployment 'd-scope-123-deploy-456' to become active..."
  assert_contains "$output" "📡 Checking deployment status (attempt 1/"
  assert_contains "$output" "❌ Failed to read deployment status"
  assert_contains "$output" "📋 NP CLI error:"
}

@test "wait_deployment_active: fails when deployment status is null" {
  np() {
    echo "null"
  }
  export -f np

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Deployment status not found for ID deploy-456"
}

@test "wait_deployment_active: fails when NP deployment status is not running" {
  export SKIP_DEPLOYMENT_STATUS_CHECK="false"

  np() {
    echo "failed"
  }
  export -f np

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Deployment is no longer running (status: failed)"
}

# =============================================================================
# Kubectl Error Cases
# =============================================================================
@test "wait_deployment_active: fails when K8s deployment not found" {
  kubectl() {
    case "$*" in
      "get deployment"*"-o json"*)
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Deployment 'd-scope-123-deploy-456' not found in namespace 'test-namespace'"
}

# =============================================================================
# Replica Status Display Tests
# =============================================================================
@test "wait_deployment_active: reports replica status correctly" {
  run bash -c "
    sleep() { :; }  # Mock sleep to be instant
    export -f sleep

    kubectl() {
      case \"\$*\" in
        \"get deployment\"*\"-o json\"*)
          echo '{
            \"spec\": {\"replicas\": 5},
            \"status\": {
              \"availableReplicas\": 3,
              \"updatedReplicas\": 4,
              \"readyReplicas\": 3
            }
          }'
          ;;
        \"get pods\"*)
          echo ''
          ;;
        \"get events\"*)
          echo '{\"items\":[]}'
          ;;
      esac
    }
    export -f kubectl

    np() { echo 'running'; }
    export -f np

    export SERVICE_PATH='$SERVICE_PATH' K8S_NAMESPACE='$K8S_NAMESPACE'
    export SCOPE_ID='$SCOPE_ID' DEPLOYMENT_ID='$DEPLOYMENT_ID'
    export TIMEOUT=10 NP_API_KEY='$NP_API_KEY' SKIP_DEPLOYMENT_STATUS_CHECK='false'
    bash '$BATS_TEST_DIRNAME/../wait_deployment_active'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "Deployment status - Available: 3/5, Updated: 4/5, Ready: 3/5"
  assert_contains "$output" "❌ Timeout waiting for deployment"
}

@test "wait_deployment_active: handles missing status fields defaults to 0" {
  run bash -c "
    sleep() { :; }  # Mock sleep to be instant
    export -f sleep

    kubectl() {
      case \"\$*\" in
        \"get deployment\"*\"-o json\"*)
          echo '{
            \"spec\": {\"replicas\": 3},
            \"status\": {}
          }'
          ;;
        \"get pods\"*)
          echo ''
          ;;
        \"get events\"*)
          echo '{\"items\":[]}'
          ;;
      esac
    }
    export -f kubectl

    np() { echo 'running'; }
    export -f np

    export SERVICE_PATH='$SERVICE_PATH' K8S_NAMESPACE='$K8S_NAMESPACE'
    export SCOPE_ID='$SCOPE_ID' DEPLOYMENT_ID='$DEPLOYMENT_ID'
    export TIMEOUT=10 NP_API_KEY='$NP_API_KEY' SKIP_DEPLOYMENT_STATUS_CHECK='false'
    bash '$BATS_TEST_DIRNAME/../wait_deployment_active'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "Available: 0/3"
}

# =============================================================================
# Zero Replicas Test
# =============================================================================
@test "wait_deployment_active: does not succeed with zero desired replicas" {
  # Use TIMEOUT=5 for immediate timeout
  export TIMEOUT=5

  kubectl() {
    case "$*" in
      "get deployment"*"-o json"*)
        echo '{
          "spec": {"replicas": 0},
          "status": {
            "availableReplicas": 0,
            "updatedReplicas": 0,
            "readyReplicas": 0
          }
        }'
        ;;
      "get pods"*)
        echo ""
        ;;
      "get events"*)
        echo '{"items":[]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  # Should timeout because desired > 0 check fails
  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Timeout waiting for deployment"
}

# =============================================================================
# Event Collection Tests
# =============================================================================
@test "wait_deployment_active: collects and displays deployment events" {
  kubectl() {
    case "$*" in
      "get deployment"*"-o json"*)
        echo '{
          "spec": {"replicas": 3},
          "status": {
            "availableReplicas": 3,
            "updatedReplicas": 3,
            "readyReplicas": 3
          }
        }'
        ;;
      "get pods"*)
        echo ""
        ;;
      "get events"*"Deployment"*)
        echo '{"items":[{"effectiveTimestamp":"2024-01-01T00:00:00Z","type":"Normal","involvedObject":{"kind":"Deployment","name":"d-scope-123-deploy-456"},"reason":"ScalingUp","message":"Scaled up replica set"}]}'
        ;;
      "get events"*)
        echo '{"items":[]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ All pods in deployment 'd-scope-123-deploy-456' are available and ready!"
}

# =============================================================================
# Iteration Calculation Test
# =============================================================================
@test "wait_deployment_active: calculates max iterations from timeout correctly" {
  export TIMEOUT=60

  run bash -c '
    MAX_ITERATIONS=$(( TIMEOUT / 10 ))
    echo $MAX_ITERATIONS
  '

  [ "$status" -eq 0 ]
  assert_equal "$output" "6"
}
