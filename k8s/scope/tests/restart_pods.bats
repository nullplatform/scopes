#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/restart_pods - restart deployment pods via rollout
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions and shared functions
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$PROJECT_ROOT/k8s/scope/require_resource"
  export -f require_hpa require_deployment find_deployment_by_label

  # Default environment
  export K8S_NAMESPACE="default-namespace"

  # Base CONTEXT with required fields
  export CONTEXT='{
    "scope": {
      "id": "scope-123",
      "current_active_deployment": "deploy-456"
    },
    "providers": {
      "container-orchestration": {
        "cluster": {
          "namespace": "provider-namespace"
        }
      }
    }
  }'

  # Mock kubectl: success flow by default
  kubectl() {
    case "$*" in
      "get deployment -n provider-namespace -l name=d-scope-123-deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "my-deployment"
        return 0
        ;;
      "rollout restart -n provider-namespace deployment/my-deployment")
        return 0
        ;;
      "rollout status -n provider-namespace deployment/my-deployment -w")
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl
}

teardown() {
  unset -f kubectl
}

# =============================================================================
# Success Flow Tests
# =============================================================================
@test "restart_pods: success flow - finds deployment, restarts, waits, completes" {
  run bash "$BATS_TEST_DIRNAME/../restart_pods"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Looking for deployment with label: name=d-scope-123-deploy-456"
  assert_contains "$output" "📝 Restarting deployment: my-deployment"
  assert_contains "$output" "🔍 Waiting for rollout to complete..."
  assert_contains "$output" "✅ Deployment restart completed successfully"
}

# =============================================================================
# Error: kubectl get deployment fails
# =============================================================================
@test "restart_pods: error when kubectl get deployment fails" {
  kubectl() {
    case "$*" in
      "get deployment -n provider-namespace -l name=d-scope-123-deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "connection refused" >&2
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../restart_pods"

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Looking for deployment with label: name=d-scope-123-deploy-456"
  assert_contains "$output" "❌ Failed to find deployment with label 'name=d-scope-123-deploy-456' in namespace 'provider-namespace'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The deployment may not exist or was not created yet"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# Error: empty deployment name returned
# =============================================================================
@test "restart_pods: error when empty deployment name returned" {
  kubectl() {
    case "$*" in
      "get deployment -n provider-namespace -l name=d-scope-123-deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo ""
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../restart_pods"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ No deployment found with label 'name=d-scope-123-deploy-456' in namespace 'provider-namespace'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# Error: rollout restart fails
# =============================================================================
@test "restart_pods: error when rollout restart fails" {
  kubectl() {
    case "$*" in
      "get deployment -n provider-namespace -l name=d-scope-123-deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "my-deployment"
        return 0
        ;;
      "rollout restart -n provider-namespace deployment/my-deployment")
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../restart_pods"

  [ "$status" -eq 1 ]
  assert_contains "$output" "📝 Restarting deployment: my-deployment"
  assert_contains "$output" "❌ Failed to restart deployment 'my-deployment'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The deployment may be in a bad state or kubectl lacks permissions"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check deployment status: kubectl describe deployment my-deployment -n provider-namespace"
}

# =============================================================================
# Error: rollout status fails/times out
# =============================================================================
@test "restart_pods: error when rollout status fails or times out" {
  kubectl() {
    case "$*" in
      "get deployment -n provider-namespace -l name=d-scope-123-deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "my-deployment"
        return 0
        ;;
      "rollout restart -n provider-namespace deployment/my-deployment")
        return 0
        ;;
      "rollout status -n provider-namespace deployment/my-deployment -w")
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../restart_pods"

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Waiting for rollout to complete..."
  assert_contains "$output" "❌ Rollout failed or timed out"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Pods may be failing to start (image pull errors, crashes, resource limits)"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check pod events: kubectl describe pods -n provider-namespace -l name=d-scope-123-deploy-456"
  assert_contains "$output" "• Check pod logs: kubectl logs -n provider-namespace -l name=d-scope-123-deploy-456 --tail=50"
}

# =============================================================================
# Namespace Resolution Tests
# =============================================================================
@test "restart_pods: uses namespace from provider" {
  kubectl() {
    case "$*" in
      *"-n provider-namespace"*)
        case "$*" in
          "get deployment"*)
            echo "my-deployment"
            return 0
            ;;
          *)
            return 0
            ;;
        esac
        ;;
      *)
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../restart_pods"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Looking for deployment with label: name=d-scope-123-deploy-456"
  assert_contains "$output" "✅ Deployment restart completed successfully"
}

@test "restart_pods: falls back to default namespace when provider namespace not set" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.namespace)')

  kubectl() {
    case "$*" in
      *"-n default-namespace"*)
        case "$*" in
          "get deployment"*)
            echo "my-deployment"
            return 0
            ;;
          *)
            return 0
            ;;
        esac
        ;;
      *)
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../restart_pods"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Deployment restart completed successfully"
}
