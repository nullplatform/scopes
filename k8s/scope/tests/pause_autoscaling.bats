#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/pause_autoscaling - pause HPA by fixing replicas
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions and shared functions
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  source "$PROJECT_ROOT/k8s/naming/resolve_names"
  export -f np_naming_lookup

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
}

teardown() {
  unset -f kubectl
}

# =============================================================================
# HPA Not Found
# =============================================================================
@test "pause_autoscaling: fails when HPA does not exist" {
  kubectl() {
    case "$*" in
      "get hpa -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo ""
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../pause_autoscaling"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ No HPA found for deployment deploy-456 in namespace 'provider-namespace'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - Autoscaling is not configured for this deployment"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   • Verify the HPA exists: kubectl get hpa -n provider-namespace -l deployment_id=deploy-456"
}

@test "pause_autoscaling: fails distinctly when the HPA lookup itself fails" {
  kubectl() {
    case "$*" in
      "get hpa -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "Error from server (Forbidden): hpas.autoscaling is forbidden"
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../pause_autoscaling"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not check the cluster for the HPA of deployment deploy-456"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - The cluster API server is unreachable"
  assert_contains "$output" "   - RBAC denies reading hpa in namespace 'provider-namespace'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   • Verify cluster connectivity and RBAC: kubectl auth can-i get hpa -n provider-namespace"
}

@test "pause_autoscaling: fails when deployment does not exist" {
  kubectl() {
    case "$*" in
      "get hpa -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "hpa-d-scope-123-deploy-456"
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace -o json")
        echo '{"spec":{"minReplicas":3,"maxReplicas":15}}'
        ;;
      "get deployment -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo ""
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../pause_autoscaling"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ No deployment found for deployment deploy-456 in namespace 'provider-namespace'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - The deployment was not created yet or was deleted"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   • Verify the deployment exists: kubectl get deployment -n provider-namespace -l deployment_id=deploy-456"
}

@test "pause_autoscaling: fails distinctly when the deployment lookup itself fails" {
  kubectl() {
    case "$*" in
      "get hpa -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "hpa-d-scope-123-deploy-456"
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace -o json")
        echo '{"spec":{"minReplicas":3,"maxReplicas":15}}'
        ;;
      "get deployment -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "Error from server (Forbidden): deployments.apps is forbidden"
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../pause_autoscaling"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not check the cluster for the deployment of deployment deploy-456"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - The cluster API server is unreachable"
  assert_contains "$output" "   - RBAC denies reading deployment in namespace 'provider-namespace'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   • Verify cluster connectivity and RBAC: kubectl auth can-i get deployment -n provider-namespace"
}

# =============================================================================
# Successful Pause Flow
# =============================================================================
@test "pause_autoscaling: complete successful pause flow" {
  kubectl() {
    case "$*" in
      "get hpa -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "hpa-d-scope-123-deploy-456"
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace -o json")
        echo '{"spec":{"minReplicas":3,"maxReplicas":15}}'
        ;;
      "get deployment -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "d-scope-123-deploy-456"
        ;;
      "get deployment d-scope-123-deploy-456 -n provider-namespace -o jsonpath"*)
        echo "7"
        ;;
      "patch hpa"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../pause_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Current HPA configuration:"
  assert_contains "$output" "   Min replicas: 3"
  assert_contains "$output" "   Max replicas: 15"
  assert_contains "$output" "📋 Current deployment replicas: 7"
  assert_contains "$output" "📝 Pausing autoscaling at 7 replicas..."
  assert_contains "$output" "✅ Autoscaling paused successfully"
  assert_contains "$output" "   HPA: hpa-d-scope-123-deploy-456"
  assert_contains "$output" "   Namespace: provider-namespace"
  assert_contains "$output" "   Fixed replicas: 7"
  assert_contains "$output" "📋 To resume autoscaling, use the resume-autoscaling action or manually patch the HPA."
}

@test "pause_autoscaling: stores original config in annotation" {
  kubectl() {
    case "$*" in
      "get hpa -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "hpa-d-scope-123-deploy-456"
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace -o json")
        echo '{"spec":{"minReplicas":2,"maxReplicas":10}}'
        ;;
      "get deployment -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
        echo "d-scope-123-deploy-456"
        ;;
      "get deployment d-scope-123-deploy-456 -n provider-namespace -o jsonpath"*)
        echo "5"
        ;;
      "patch hpa"*)
        if [[ "$*" == *"nullplatform.com/autoscaling-paused"* ]]; then
          return 0
        fi
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../pause_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Autoscaling paused successfully"
}

# =============================================================================
# Namespace Resolution Tests
# =============================================================================
@test "pause_autoscaling: uses namespace from provider" {
  kubectl() {
    case "$*" in
      *"-n provider-namespace"*)
        case "$*" in
          "get hpa -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
            echo "hpa-d-scope-123-deploy-456"
            ;;
          "get deployment -n provider-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
            echo "d-scope-123-deploy-456"
            ;;
          "get hpa"*"-o json"*)
            echo '{"spec":{"minReplicas":2,"maxReplicas":10}}'
            ;;
          "get deployment"*)
            echo "5"
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

  run bash "$BATS_TEST_DIRNAME/../pause_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "   Namespace: provider-namespace"
}

@test "pause_autoscaling: falls back to default namespace" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.namespace)')

  kubectl() {
    case "$*" in
      *"-n default-namespace"*)
        case "$*" in
          "get hpa -n default-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
            echo "hpa-d-scope-123-deploy-456"
            ;;
          "get deployment -n default-namespace -l deployment_id=deploy-456 -o jsonpath={.items[0].metadata.name}")
            echo "d-scope-123-deploy-456"
            ;;
          "get hpa"*"-o json"*)
            echo '{"spec":{"minReplicas":2,"maxReplicas":10}}'
            ;;
          "get deployment"*)
            echo "5"
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

  run bash "$BATS_TEST_DIRNAME/../pause_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "   Namespace: default-namespace"
}
