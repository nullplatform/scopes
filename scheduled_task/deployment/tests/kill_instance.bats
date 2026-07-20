#!/usr/bin/env bats
# =============================================================================
# Unit tests for scheduled_task deployment/kill_instance - job pod termination
#
# scheduled_task pods are owned by Job -> CronJob (job-<scope>-<deployment>),
# unlike the base k8s scope where pods are owned by ReplicaSet -> Deployment.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"
  export KILL_STATE="$BATS_TEST_TMPDIR/deleted"
  rm -f "$KILL_STATE"

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

  # Default mock: pod owned by a Job that belongs to the expected CronJob.
  # A state file flips the plain (no -o) pod existence check to "gone" once
  # `kubectl delete` has run, exercising the happy termination path.
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
                echo "job-scope-123-deploy-456-abc"
              fi
              return 0
            fi
            # existence check (no -o): gone once deleted
            [[ -f "$KILL_STATE" ]] && return 1
            return 0
            ;;
          job)
            if [[ "$*" == *"-o jsonpath"* ]]; then
              if [[ "$*" == *"ownerReferences"* ]]; then
                echo "job-scope-123-deploy-456"
              elif [[ "$*" == *"active"* ]]; then
                echo "0"
              elif [[ "$*" == *"succeeded"* ]]; then
                echo "1"
              elif [[ "$*" == *"failed"* ]]; then
                echo "0"
              fi
              return 0
            fi
            return 0
            ;;
        esac
        ;;
      delete)
        touch "$KILL_STATE"
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
@test "kill_instance: successfully kills job pod with correct logging" {
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
  assert_contains "$output" "📋 Pod: my-pod-abc123 | Status: Running | Node: node-1 | Started: 2024-01-01T00:00:00Z"
  # Ownership (Job -> CronJob)
  assert_contains "$output" "📋 Pod ownership: Job=job-scope-123-deploy-456-abc -> CronJob=job-scope-123-deploy-456"
  # Delete operation
  assert_contains "$output" "📝 Deleting pod my-pod-abc123 with 30s grace period..."
  assert_contains "$output" "📝 Waiting for pod termination..."
  assert_contains "$output" "✅ Pod successfully terminated and removed"
  # Job status
  assert_contains "$output" "📋 Checking job status after pod deletion..."
  assert_contains "$output" "📋 Job job-scope-123-deploy-456-abc: active=0, succeeded=1, failed=0"
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
@test "kill_instance: warns when pod belongs to a different scheduled task" {
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
                echo "job-scope-123-deploy-456-abc"
              fi
              return 0
            fi
            [[ -f "$KILL_STATE" ]] && return 1
            return 0
            ;;
          job)
            if [[ "$*" == *"-o jsonpath"* ]]; then
              if [[ "$*" == *"ownerReferences"* ]]; then
                echo "job-scope-123-different-deploy"  # Different CronJob
              elif [[ "$*" == *"active"* ]]; then
                echo "0"
              fi
              return 0
            fi
            return 0
            ;;
        esac
        ;;
      delete)
        touch "$KILL_STATE"
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
  assert_contains "$output" "⚠️  Pod does not belong to expected scheduled task job-scope-123-deploy-456 (continuing anyway)"
}

@test "kill_instance: warns when pod ownership cannot be verified" {
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
                echo ""  # Bare pod, no owner
              fi
              return 0
            fi
            [[ -f "$KILL_STATE" ]] && return 1
            return 0
            ;;
          job)
            [[ -f "$KILL_STATE" ]] && return 1
            return 0
            ;;
        esac
        ;;
      delete)
        touch "$KILL_STATE"
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
  assert_contains "$output" "⚠️  Could not verify pod ownership"
  # With no owner Job, the post-deletion job lookup cannot resolve one either
  assert_contains "$output" "⚠️  Job for pod not found (it may have already completed)"
}

@test "kill_instance: warns when pod still exists after deletion" {
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
                echo "job-scope-123-deploy-456-abc"
              fi
              return 0
            fi
            return 0  # Pod still exists
            ;;
          job)
            if [[ "$*" == *"-o jsonpath"* ]]; then
              if [[ "$*" == *"ownerReferences"* ]]; then
                echo "job-scope-123-deploy-456"
              elif [[ "$*" == *"active"* ]]; then
                echo "1"
              fi
              return 0
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
  # Job still active -> replacement pod may be started
  assert_contains "$output" "📋 Checking job status after pod deletion..."
  assert_contains "$output" "📋 Job job-scope-123-deploy-456-abc: active=1, succeeded=0, failed=0"
  assert_contains "$output" "📋 Job is still active; Kubernetes may start a replacement pod (backoffLimit permitting)"
}

@test "kill_instance: warns when job already completed after pod deletion" {
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
                echo "job-scope-123-deploy-456-abc"
              fi
              return 0
            fi
            [[ -f "$KILL_STATE" ]] && return 1
            return 0
            ;;
          job)
            if [[ "$*" == *"-o jsonpath"* ]]; then
              if [[ "$*" == *"ownerReferences"* ]]; then
                echo "job-scope-123-deploy-456"
              fi
              return 0
            fi
            # Job existence check: gone once the pod was deleted
            [[ -f "$KILL_STATE" ]] && return 1
            return 0
            ;;
        esac
        ;;
      delete)
        touch "$KILL_STATE"
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
  assert_contains "$output" "⚠️  Job for pod not found (it may have already completed)"
}
