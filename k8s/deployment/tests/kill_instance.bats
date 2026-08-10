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
              return 0
            fi
            # Bare existence check (no -o jsonpath): the script calls this
            # with identical args once before the delete (pod must exist)
            # and once after (pod must be gone, since delete+wait succeed
            # below). Count calls so the second one reflects a real kubectl
            # after a successful deletion instead of pretending the pod is
            # still there.
            KUBECTL_GET_POD_CALLS=$((${KUBECTL_GET_POD_CALLS:-0} + 1))
            [ "$KUBECTL_GET_POD_CALLS" -eq 1 ]
            return $?
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
  local expected
  expected=$(cat <<'EOF'
🔍 Starting instance kill operation...
📋 Deployment ID: deploy-456
📋 Instance name: my-pod-abc123
📋 Scope ID: scope-123
📋 Namespace: test-namespace
🔍 Verifying pod exists...
📋 Fetching pod details...
📋 Pod: my-pod-abc123 | Status: Running | Node: node-1 | Started: 2024-01-01T00:00:00Z
📋 Pod ownership: ReplicaSet=my-replicaset-abc -> Deployment=d-scope-123-deploy-456
📝 Deleting pod my-pod-abc123 with 30s grace period...
pod deleted
📝 Waiting for pod termination...
✅ Pod successfully terminated and removed
📋 Checking deployment status after pod deletion...
📋 Deployment d-scope-123-deploy-456: desired=3, ready=2, available=2
📋 Kubernetes will automatically create a replacement pod
✨ Instance kill operation completed for my-pod-abc123
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'
🔍 Starting instance kill operation...
❌ deployment_id parameter not found
💡 Possible causes:
   - Parameter not provided in action request
   - Context structure is different than expected
🔧 How to fix:
   - Ensure deployment_id is passed in the action parameters
EOF
)
  assert_equal "$output" "$expected"
}

@test "kill_instance: fails with troubleshooting when instance_id missing" {
  export CONTEXT='{
    "parameters": {
      "deployment_id": "deploy-456"
    }
  }'

  run bash "$BATS_TEST_DIRNAME/../kill_instance"

  [ "$status" -eq 1 ]
  local expected
  expected=$(cat <<'EOF'
🔍 Starting instance kill operation...
❌ instance_id parameter not found
💡 Possible causes:
   - Parameter not provided in action request
   - Context structure is different than expected
🔧 How to fix:
   - Ensure instance_id is passed in the action parameters
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'
🔍 Starting instance kill operation...
📋 Deployment ID: deploy-456
📋 Instance name: my-pod-abc123
❌ scope_id not found in context
💡 Possible causes:
   - Context missing scope information
   - Action invoked outside of scope context
🔧 How to fix:
   - Verify the action is invoked with proper scope context
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'
🔍 Starting instance kill operation...
📋 Deployment ID: deploy-456
📋 Instance name: my-pod-abc123
📋 Scope ID: scope-123
📋 Namespace: test-namespace
🔍 Verifying pod exists...
❌ Pod my-pod-abc123 not found in namespace test-namespace
💡 Possible causes:
   - Pod was already terminated
   - Pod name is incorrect
   - Pod exists in a different namespace
🔧 How to fix:
   - List pods: kubectl get pods -n test-namespace -l scope_id=scope-123
EOF
)
  assert_equal "$output" "$expected"
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
              return 0
            fi
            # Bare existence check (no -o jsonpath): called once before the
            # delete (pod must exist) and once after (pod must be gone,
            # since delete+wait both succeed below). Count calls so the
            # second one reflects a real kubectl after a successful
            # deletion instead of pretending the pod is still there.
            KUBECTL_GET_POD_CALLS=$((${KUBECTL_GET_POD_CALLS:-0} + 1))
            [ "$KUBECTL_GET_POD_CALLS" -eq 1 ]
            return $?
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
  assert_contains "$output" "⚠️  Pod does not belong to expected deployment d-scope-123-deploy-456 (continuing anyway)"
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
  assert_contains "$output" "⚠️  Pod still exists after deletion attempt (status: Terminating)"
}
