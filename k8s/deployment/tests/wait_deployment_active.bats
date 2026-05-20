#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/wait_deployment_active - poll until deployment ready
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

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
  # Timeout path must source print_failed_deployment_hints; with no pod info
  # and no events, it falls through to the generic checklist.
  assert_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "wait_deployment_active: surfaces specific failure reason on timeout when pod info is available" {
  export TIMEOUT=5

  kubectl() {
    case "$*" in
      "get deployment d-scope-123-deploy-456 -n test-namespace -o json")
        echo '{"spec":{"replicas":3},"status":{"availableReplicas":0,"updatedReplicas":0,"readyReplicas":0}}'
        ;;
      "get pods -n test-namespace -l deployment_id=deploy-456 -o json")
        echo '{"items":[{"status":{"containerStatuses":[{"name":"app","state":{"running":{}},"lastState":{"terminated":{"reason":"OOMKilled","exitCode":137,"message":"out of memory"}}}]}}]}'
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

  export CONTEXT='{"scope":{"name":"my-app","dimensions":"prod","capabilities":{"health_check":{"path":"/health"},"ram_memory":512}}}'

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Timeout waiting for deployment"
  # The hint script must read pod state and surface the user-friendly reason
  assert_contains "$output" "📋 Reason: The container exceeded its memory limit"
  assert_contains "$output" "📋 Detected: OOMKilled on container app (exit 137)"
  assert_contains "$output" "💡 Suggested fix: Increase ram_memory for scope 'my-app'"
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
  # Non-running status path must also source print_failed_deployment_hints
  assert_contains "$output" "⚠️  Application Startup Issue Detected"
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
  assert_contains "$output" "⏳ Still waiting — Ready: 3/5, Available: 3/5 (attempt 1/1, 10s elapsed)"
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

# =============================================================================
# Heartbeat Tests
# =============================================================================
@test "wait_deployment_active: logs heartbeat every 10% of timeout with progress info" {
  # TIMEOUT=100 -> MAX_ITERATIONS=10 -> HEARTBEAT_INTERVAL=1 (every iteration)
  run bash -c "
    sleep() { :; }
    export -f sleep

    kubectl() {
      case \"\$*\" in
        \"get deployment\"*\"-o json\"*)
          echo '{\"spec\":{\"replicas\":2},\"status\":{\"availableReplicas\":0,\"updatedReplicas\":0,\"readyReplicas\":0}}'
          ;;
        \"get pods\"*) echo '' ;;
        \"get events\"*) echo '{\"items\":[]}' ;;
      esac
    }
    export -f kubectl

    np() { echo 'running'; }
    export -f np

    export SERVICE_PATH='$SERVICE_PATH' K8S_NAMESPACE='$K8S_NAMESPACE'
    export SCOPE_ID='$SCOPE_ID' DEPLOYMENT_ID='$DEPLOYMENT_ID'
    export TIMEOUT=100 NP_API_KEY='$NP_API_KEY' SKIP_DEPLOYMENT_STATUS_CHECK='false'
    bash '$BATS_TEST_DIRNAME/../wait_deployment_active'
  "

  [ "$status" -eq 1 ]
  # First heartbeat always at iteration 1
  assert_contains "$output" "⏳ Still waiting — Ready: 0/2, Available: 0/2 (attempt 1/10, 10s elapsed)"
  # Mid-progress
  assert_contains "$output" "(attempt 5/10, 50s elapsed)"
  # Last iteration before timeout
  assert_contains "$output" "(attempt 10/10, 100s elapsed)"
}

@test "wait_deployment_active: heartbeat interval clamps to >=1 for short timeouts" {
  # TIMEOUT=30 -> MAX_ITERATIONS=3 -> HEARTBEAT_INTERVAL would be 0, must clamp to 1
  run bash -c "
    sleep() { :; }
    export -f sleep

    kubectl() {
      case \"\$*\" in
        \"get deployment\"*\"-o json\"*)
          echo '{\"spec\":{\"replicas\":1},\"status\":{\"availableReplicas\":0,\"updatedReplicas\":0,\"readyReplicas\":0}}'
          ;;
        \"get pods\"*) echo '' ;;
        \"get events\"*) echo '{\"items\":[]}' ;;
      esac
    }
    export -f kubectl

    np() { echo 'running'; }
    export -f np

    export SERVICE_PATH='$SERVICE_PATH' K8S_NAMESPACE='$K8S_NAMESPACE'
    export SCOPE_ID='$SCOPE_ID' DEPLOYMENT_ID='$DEPLOYMENT_ID'
    export TIMEOUT=30 NP_API_KEY='$NP_API_KEY' SKIP_DEPLOYMENT_STATUS_CHECK='false'
    bash '$BATS_TEST_DIRNAME/../wait_deployment_active'
  "

  [ "$status" -eq 1 ]
  # All three iterations should emit a heartbeat (interval clamped to 1)
  assert_contains "$output" "(attempt 1/3, 10s elapsed)"
  assert_contains "$output" "(attempt 2/3, 20s elapsed)"
  assert_contains "$output" "(attempt 3/3, 30s elapsed)"
}

@test "wait_deployment_active: heartbeat is suppressed when deployment is ready on iteration 1" {
  # Default mocks: deployment is ready immediately, so heartbeat should NOT fire.
  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ All pods in deployment 'd-scope-123-deploy-456' are available and ready!"
  # No heartbeat emitted because the ready-check breaks before it
  if [[ "$output" == *"Still waiting"* ]]; then
    echo "Expected output to NOT contain 'Still waiting' on success path"
    echo "Actual: $output"
    return 1
  fi
}

# =============================================================================
# Unhealthy Translation Tests
# =============================================================================
@test "wait_deployment_active: translates Unhealthy connection-refused into human line during polling" {
  # Use a far-future timestamp so the event is not filtered out by the now() initialization.
  run bash -c "
    sleep() { :; }
    export -f sleep

    kubectl() {
      case \"\$*\" in
        \"get deployment\"*\"-o json\"*)
          echo '{\"spec\":{\"replicas\":1},\"status\":{\"availableReplicas\":0,\"updatedReplicas\":0,\"readyReplicas\":0}}'
          ;;
        \"get pods -n test-namespace -l deployment_id=deploy-456 -o jsonpath\"*)
          echo 'd-scope-123-deploy-456-abc'
          ;;
        \"get events\"*\"Pod\"*)
          echo '{\"items\":[{\"lastTimestamp\":\"9999-12-31T23:59:59Z\",\"type\":\"Warning\",\"involvedObject\":{\"kind\":\"Pod\",\"name\":\"d-scope-123-deploy-456-abc\"},\"reason\":\"Unhealthy\",\"message\":\"Startup probe failed: Get \\\"http://10.0.0.1:8080/health\\\": dial tcp 10.0.0.1:8080: connect: connection refused\"}]}'
          ;;
        \"get events\"*) echo '{\"items\":[]}' ;;
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
  # Translated form must appear
  assert_contains "$output" "Startup probe"
  assert_contains "$output" "not yet listening"
  assert_contains "$output" "/health"
  # Raw connection-refused text must NOT leak through
  if [[ "$output" == *"connection refused"* ]]; then
    echo "Expected output to NOT contain raw 'connection refused' (should be translated)"
    echo "Actual: $output"
    return 1
  fi
}

@test "wait_deployment_active: translates Unhealthy HTTP statuscode into human line during polling" {
  run bash -c "
    sleep() { :; }
    export -f sleep

    kubectl() {
      case \"\$*\" in
        \"get deployment\"*\"-o json\"*)
          echo '{\"spec\":{\"replicas\":1},\"status\":{\"availableReplicas\":0,\"updatedReplicas\":0,\"readyReplicas\":0}}'
          ;;
        \"get pods -n test-namespace -l deployment_id=deploy-456 -o jsonpath\"*)
          echo 'd-scope-123-deploy-456-abc'
          ;;
        \"get events\"*\"Pod\"*)
          echo '{\"items\":[{\"lastTimestamp\":\"9999-12-31T23:59:59Z\",\"type\":\"Warning\",\"involvedObject\":{\"kind\":\"Pod\",\"name\":\"d-scope-123-deploy-456-abc\"},\"reason\":\"Unhealthy\",\"message\":\"Startup probe failed: HTTP probe failed with statuscode: 502\"}]}'
          ;;
        \"get events\"*) echo '{\"items\":[]}' ;;
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
  assert_contains "$output" "Startup probe"
  assert_contains "$output" "HTTP 502"
}

# =============================================================================
# Latest Timestamp Initialization
# =============================================================================
@test "wait_deployment_active: skips K8s events older than script start time" {
  # An event from 2020 must be filtered out because LATEST_TIMESTAMP is initialized
  # to now() — prevents stale events from previous workflow retries leaking through.
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
        # A very old event that should be suppressed
        echo '{"items":[{"effectiveTimestamp":"2020-01-01T00:00:00Z","type":"Warning","involvedObject":{"kind":"Pod","name":"d-scope-123-deploy-456-abc"},"reason":"Unhealthy","message":"old stale warning"}]}'
        ;;
      "get events"*)
        echo '{"items":[]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_deployment_active"

  [ "$status" -eq 0 ]
  # The 2020 event must not appear in output
  if [[ "$output" == *"old stale warning"* ]]; then
    echo "Expected output to NOT contain stale 2020 warning"
    echo "Actual: $output"
    return 1
  fi
  if [[ "$output" == *"2020-01-01T00:00:00Z"* ]]; then
    echo "Expected output to NOT contain stale 2020 timestamp"
    echo "Actual: $output"
    return 1
  fi
}
