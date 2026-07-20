#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/kill_instance - pod termination
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"

  export CONTEXT='{
    "parameters": {
      "deployment_id": "deploy-456",
      "instance_id": "my-pod-abc123"
    },
    "tags": {
      "scope_id": "scope-123"
    },
    "providers": {
      "container-orchestration": {
        "cluster": {
          "namespace": "test-namespace"
        }
      }
    }
  }'

  kubectl() {
    case "$1" in
      get)
        case "$2" in
          pod)
            if [[ "$*" == *"-o jsonpath"* ]]; then
              if [[ "$*" == *"phase"* ]]; then
                echo "Running"
              elif [[ "$*" == *"nodeName"* ]]; then
                echo "node-1"
              elif [[ "$*" == *"startTime"* ]]; then
                echo "2024-01-01T00:00:00Z"
              elif [[ "$*" == *"ownerReferences"* ]]; then
                echo "my-replicaset-abc"
              fi
            fi
            return 0
            ;;
          replicaset)
            echo "d-scope-123-deploy-456"
            return 0
            ;;
          deployment)
            if [[ "$*" == *"replicas"* ]]; then
              echo "3"
            elif [[ "$*" == *"readyReplicas"* ]]; then
              echo "2"
            elif [[ "$*" == *"availableReplicas"* ]]; then
              echo "2"
            fi
            return 0
            ;;
        esac
        ;;
      delete)
        echo "pod deleted"
        return 0
        ;;
      wait)
        return 0
        ;;
    esac
    return 0
  }
  export -f kubectl
}

teardown() {
  unset CONTEXT
  unset -f kubectl
}

# =============================================================================
# Success Case
# =============================================================================
@test "kill_instance: successfully kills pod with correct logging" {
  run bash "$BATS_TEST_DIRNAME/../kill_instance"

  [ "$status" -eq 0 ]
  # Start message
  assert_contains "$output" "🔍 Starting instance kill operation..."
  # Parameter display
  assert_contains "$output" "📋 Deployment ID: deploy-456"
  assert_contains "$output" "📋 Instance name: my-pod-abc123"
  assert_contains "$output" "📋 Scope ID: scope-123"
  assert_contains "$output" "📋 Namespace: test-namespace"
  # Pod verification
  assert_contains "$output" "🔍 Verifying pod exists..."
  assert_contains "$output" "📋 Fetching pod details..."
  # Delete operation
  assert_contains "$output" "📝 Deleting pod my-pod-abc123 with 30s grace period..."
  assert_contains "$output" "📝 Waiting for pod termination..."
  # Deployment status
  assert_contains "$output" "📋 Checking deployment status after pod deletion..."
  # Completion
  assert_contains "$output" "✨ Instance kill operation completed for my-pod-abc123"
}

# =============================================================================
# Error Cases
# =============================================================================
@test "kill_instance: fails with troubleshooting when deployment_id missing" {
  export CONTEXT='{
    "parameters": {
      "instance_id": "my-pod-abc123"
    }
  }'

  run bash "$BATS_TEST_DIRNAME/../kill_instance"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ deployment_id parameter not found"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Parameter not provided in action request"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Ensure deployment_id is passed in the action parameters"
}

@test "kill_instance: fails with troubleshooting when instance_id missing" {
  export CONTEXT='{
    "parameters": {
      "deployment_id": "deploy-456"
    }
  }'

  run bash "$BATS_TEST_DIRNAME/../kill_instance"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ instance_id parameter not found"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Parameter not provided in action request"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Ensure instance_id is passed in the action parameters"
}

@test "kill_instance: fails with troubleshooting when scope_id missing" {
  export CONTEXT='{
    "parameters": {
      "deployment_id": "deploy-456",
      "instance_id": "my-pod-abc123"
    }
  }'

  run bash "$BATS_TEST_DIRNAME/../kill_instance"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ scope_id not found in context"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Context missing scope information"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify the action is invoked with proper scope context"
}

@test "kill_instance: fails with troubleshooting when pod not found" {
  kubectl() {
    case "$1" in
      get)
        if [[ "$2" == "pod" ]] && [[ "$*" != *"-o"* ]]; then
          return 1
        fi
        ;;
    esac
    return 0
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../kill_instance"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Pod my-pod-abc123 not found in namespace test-namespace"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Pod was already terminated"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "kubectl get pods"
}

# =============================================================================
# Warning Cases
# =============================================================================
@test "kill_instance: warns when pod belongs to different deployment" {
  kubectl() {
    case "$1" in
      get)
        case "$2" in
          pod)
            if [[ "$*" == *"-o jsonpath"* ]]; then
              if [[ "$*" == *"phase"* ]]; then
                echo "Running"
              elif [[ "$*" == *"nodeName"* ]]; then
                echo "node-1"
              elif [[ "$*" == *"startTime"* ]]; then
                echo "2024-01-01T00:00:00Z"
              elif [[ "$*" == *"ownerReferences"* ]]; then
                echo "my-replicaset-abc"
              fi
            fi
            return 0
            ;;
          replicaset)
            echo "d-scope-123-different-deploy"  # Different deployment
            return 0
            ;;
          deployment)
            if [[ "$*" == *"replicas"* ]]; then
              echo "3"
            fi
            return 0
            ;;
        esac
        ;;
      delete)
        return 0
        ;;
      wait)
        return 0
        ;;
    esac
    return 0
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../kill_instance"

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  Pod does not belong to expected deployment d-scope-123-deploy-456"
}

@test "kill_instance: warns when pod still exists after deletion" {
  local delete_called=0
  kubectl() {
    case "$1" in
      get)
        case "$2" in
          pod)
            if [[ "$*" == *"-o jsonpath"* ]]; then
              if [[ "$*" == *"phase"* ]]; then
                echo "Terminating"
              elif [[ "$*" == *"nodeName"* ]]; then
                echo "node-1"
              elif [[ "$*" == *"startTime"* ]]; then
                echo "2024-01-01T00:00:00Z"
              elif [[ "$*" == *"ownerReferences"* ]]; then
                echo "my-replicaset-abc"
              fi
            fi
            return 0  # Pod still exists
            ;;
          replicaset)
            echo "d-scope-123-deploy-456"
            return 0
            ;;
          deployment)
            if [[ "$*" == *"replicas"* ]]; then
              echo "3"
            fi
            return 0
            ;;
        esac
        ;;
      delete)
        return 0
        ;;
      wait)
        return 1  # Timeout
        ;;
    esac
    return 0
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../kill_instance"

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  Pod deletion timeout reached"
  assert_contains "$output" "⚠️  Pod still exists after deletion attempt"
}
