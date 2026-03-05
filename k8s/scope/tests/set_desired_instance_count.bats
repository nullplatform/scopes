#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/set_desired_instance_count - set deployment replicas
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions and shared functions
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  source "$PROJECT_ROOT/k8s/scope/require_resource"
  export -f require_hpa require_deployment find_deployment_by_label

  # Default environment
  export K8S_NAMESPACE="default-namespace"
  export ACTION_PARAMETERS_DESIRED_INSTANCES="5"

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
  rm -f "${REPLICAS_COUNTER_FILE:-}" "${HPA_MIN_COUNTER_FILE:-}" "${HPA_MAX_COUNTER_FILE:-}"
}

# =============================================================================
# Parameter Validation Tests
# =============================================================================
@test "set_desired_instance_count: fails when DESIRED_INSTANCES not set" {
  unset ACTION_PARAMETERS_DESIRED_INSTANCES

  run bash "$BATS_TEST_DIRNAME/../set_desired_instance_count"

  [ "$status" -eq 1 ]
  assert_contains "$output" "📝 Setting desired instance count..."
  assert_contains "$output" "❌ desired_instances parameter not found"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The ACTION_PARAMETERS_DESIRED_INSTANCES environment variable is not set"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Set the desired_instances parameter in the action configuration"
}

@test "set_desired_instance_count: fails when DESIRED_INSTANCES is empty" {
  export ACTION_PARAMETERS_DESIRED_INSTANCES=""

  run bash "$BATS_TEST_DIRNAME/../set_desired_instance_count"

  [ "$status" -eq 1 ]
  assert_contains "$output" "📝 Setting desired instance count..."
  assert_contains "$output" "❌ desired_instances parameter not found"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The ACTION_PARAMETERS_DESIRED_INSTANCES environment variable is not set"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Set the desired_instances parameter in the action configuration"
}

# =============================================================================
# Deployment Not Found
# =============================================================================
@test "set_desired_instance_count: fails when deployment not found" {
  kubectl() {
    case "$*" in
      "get deployment d-scope-123-deploy-456 -n provider-namespace")
        return 1
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../set_desired_instance_count"

  [ "$status" -eq 1 ]
  assert_contains "$output" "📋 Desired instances: 5"
  assert_contains "$output" "📋 Deployment: d-scope-123-deploy-456"
  assert_contains "$output" "📋 Namespace: provider-namespace"
  assert_contains "$output" "🔍 Looking for deployment 'd-scope-123-deploy-456' in namespace 'provider-namespace'..."
  assert_contains "$output" "❌ Deployment 'd-scope-123-deploy-456' not found in namespace 'provider-namespace'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The deployment may not exist or was not created yet"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify the deployment exists: kubectl get deployment -n provider-namespace"
  assert_contains "$output" "• Check that scope scope-123 has an active deployment"
}

# =============================================================================
# No HPA Path - Complete Flow
# =============================================================================
@test "set_desired_instance_count: complete flow with no HPA" {
  export REPLICAS_COUNTER_FILE=$(mktemp)
  echo "0" > "$REPLICAS_COUNTER_FILE"

  kubectl() {
    case "$*" in
      "get deployment d-scope-123-deploy-456 -n provider-namespace")
        return 0
        ;;
      "get deployment d-scope-123-deploy-456 -n provider-namespace -o jsonpath"*)
        if [[ "$*" == *"readyReplicas"* ]]; then
          echo "5"
        else
          local count
          count=$(cat "$REPLICAS_COUNTER_FILE")
          echo $(( count + 1 )) > "$REPLICAS_COUNTER_FILE"
          if [[ "$count" == "0" ]]; then
            echo "3"  # CURRENT_REPLICAS
          else
            echo "5"  # FINAL_REPLICAS (after scale)
          fi
        fi
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace")
        return 1  # No HPA
        ;;
      "scale deployment"*)
        return 0
        ;;
      "rollout status"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../set_desired_instance_count"
  rm -f "$REPLICAS_COUNTER_FILE"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Setting desired instance count..."
  assert_contains "$output" "📋 Desired instances: 5"
  assert_contains "$output" "📋 Deployment: d-scope-123-deploy-456"
  assert_contains "$output" "📋 Namespace: provider-namespace"
  assert_contains "$output" "📋 Current replicas: 3"
  assert_contains "$output" "📋 No HPA found for this deployment"
  assert_contains "$output" "📝 Updating deployment (no HPA)..."
  assert_contains "$output" "✅ Deployment scaled to 5 replicas"
  assert_contains "$output" "🔍 Waiting for deployment rollout to complete..."
  assert_contains "$output" "📋 Final status:"
  assert_contains "$output" "   Deployment replicas: 5"
  assert_contains "$output" "   Ready replicas: 5"
  assert_contains "$output" "✨ Instance count successfully set to 5"
}

# =============================================================================
# Active HPA Path - Complete Flow
# =============================================================================
@test "set_desired_instance_count: complete flow with active HPA" {
  export REPLICAS_COUNTER_FILE=$(mktemp)
  export HPA_MIN_COUNTER_FILE=$(mktemp)
  export HPA_MAX_COUNTER_FILE=$(mktemp)
  echo "0" > "$REPLICAS_COUNTER_FILE"
  echo "0" > "$HPA_MIN_COUNTER_FILE"
  echo "0" > "$HPA_MAX_COUNTER_FILE"

  kubectl() {
    case "$*" in
      "get deployment d-scope-123-deploy-456 -n provider-namespace")
        return 0
        ;;
      "get deployment d-scope-123-deploy-456 -n provider-namespace -o jsonpath"*)
        if [[ "$*" == *"readyReplicas"* ]]; then
          echo "5"
        else
          local count
          count=$(cat "$REPLICAS_COUNTER_FILE")
          echo $(( count + 1 )) > "$REPLICAS_COUNTER_FILE"
          if [[ "$count" == "0" ]]; then
            echo "3"  # CURRENT_REPLICAS
          else
            echo "5"  # FINAL_REPLICAS
          fi
        fi
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace")
        return 0  # HPA exists
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace -o jsonpath"*)
        if [[ "$*" == *"autoscaling-paused"* ]]; then
          echo ""  # Not paused
        elif [[ "$*" == *"minReplicas"* ]]; then
          local count
          count=$(cat "$HPA_MIN_COUNTER_FILE")
          echo $(( count + 1 )) > "$HPA_MIN_COUNTER_FILE"
          if [[ "$count" == "0" ]]; then
            echo "2"   # Before patch
          else
            echo "5"   # After patch (final status)
          fi
        elif [[ "$*" == *"maxReplicas"* ]]; then
          local count
          count=$(cat "$HPA_MAX_COUNTER_FILE")
          echo $(( count + 1 )) > "$HPA_MAX_COUNTER_FILE"
          if [[ "$count" == "0" ]]; then
            echo "10"  # Before patch
          else
            echo "5"   # After patch (final status)
          fi
        fi
        ;;
      "patch hpa"*)
        return 0
        ;;
      "rollout status"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../set_desired_instance_count"
  rm -f "$REPLICAS_COUNTER_FILE" "$HPA_MIN_COUNTER_FILE" "$HPA_MAX_COUNTER_FILE"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Setting desired instance count..."
  assert_contains "$output" "📋 Desired instances: 5"
  assert_contains "$output" "📋 Current replicas: 3"
  assert_contains "$output" "📋 HPA found: hpa-d-scope-123-deploy-456"
  assert_contains "$output" "📋 HPA is currently ACTIVE"
  assert_contains "$output" "📝 Updating HPA for active autoscaling..."
  assert_contains "$output" "📋 Current HPA range: 2 - 10 replicas"
  assert_contains "$output" "📋 Setting desired instances to 5 by updating HPA range"
  assert_contains "$output" "✅ HPA updated: min=5, max=5"
  assert_contains "$output" "🔍 Waiting for deployment rollout to complete..."
  assert_contains "$output" "📋 Final status:"
  assert_contains "$output" "   Deployment replicas: 5"
  assert_contains "$output" "   Ready replicas: 5"
  assert_contains "$output" "   HPA range: 5 - 5 replicas"
  assert_contains "$output" "✨ Instance count successfully set to 5"
}

# =============================================================================
# Paused HPA Path - Complete Flow
# =============================================================================
@test "set_desired_instance_count: complete flow with paused HPA" {
  export REPLICAS_COUNTER_FILE=$(mktemp)
  echo "0" > "$REPLICAS_COUNTER_FILE"

  kubectl() {
    case "$*" in
      "get deployment d-scope-123-deploy-456 -n provider-namespace")
        return 0
        ;;
      "get deployment d-scope-123-deploy-456 -n provider-namespace -o jsonpath"*)
        if [[ "$*" == *"readyReplicas"* ]]; then
          echo "5"
        else
          local count
          count=$(cat "$REPLICAS_COUNTER_FILE")
          echo $(( count + 1 )) > "$REPLICAS_COUNTER_FILE"
          if [[ "$count" == "0" ]]; then
            echo "3"  # CURRENT_REPLICAS
          else
            echo "5"  # FINAL_REPLICAS
          fi
        fi
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace")
        return 0  # HPA exists
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace -o jsonpath"*)
        if [[ "$*" == *"autoscaling-paused"* ]]; then
          echo '{"originalMinReplicas":2,"originalMaxReplicas":10}'  # Paused
        elif [[ "$*" == *"minReplicas"* ]]; then
          echo "5"
        elif [[ "$*" == *"maxReplicas"* ]]; then
          echo "5"
        fi
        ;;
      "scale deployment"*)
        return 0
        ;;
      "rollout status"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../set_desired_instance_count"
  rm -f "$REPLICAS_COUNTER_FILE"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Setting desired instance count..."
  assert_contains "$output" "📋 Current replicas: 3"
  assert_contains "$output" "📋 HPA found: hpa-d-scope-123-deploy-456"
  assert_contains "$output" "📋 HPA is currently PAUSED"
  assert_contains "$output" "📝 Updating deployment (HPA paused)..."
  assert_contains "$output" "✅ Deployment scaled to 5 replicas"
  assert_contains "$output" "🔍 Waiting for deployment rollout to complete..."
  assert_contains "$output" "📋 Final status:"
  assert_contains "$output" "   Deployment replicas: 5"
  assert_contains "$output" "   Ready replicas: 5"
  assert_contains "$output" "   HPA range: 5 - 5 replicas"
  assert_contains "$output" "✨ Instance count successfully set to 5"
}

# =============================================================================
# Namespace Resolution Tests
# =============================================================================
@test "set_desired_instance_count: uses namespace from provider" {
  kubectl() {
    case "$*" in
      "get deployment d-scope-123-deploy-456 -n provider-namespace")
        return 0
        ;;
      "get deployment d-scope-123-deploy-456 -n provider-namespace -o jsonpath"*)
        if [[ "$*" == *"readyReplicas"* ]]; then
          echo "5"
        else
          echo "3"
        fi
        ;;
      "get hpa hpa-d-scope-123-deploy-456 -n provider-namespace")
        return 1
        ;;
      "scale deployment"*)
        return 0
        ;;
      "rollout status"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../set_desired_instance_count"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Namespace: provider-namespace"
  assert_contains "$output" "🔍 Looking for deployment 'd-scope-123-deploy-456' in namespace 'provider-namespace'..."
}

@test "set_desired_instance_count: falls back to default namespace" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.namespace)')

  kubectl() {
    case "$*" in
      *"-n default-namespace"*)
        case "$*" in
          "get deployment"*"-o jsonpath"*)
            if [[ "$*" == *"readyReplicas"* ]]; then
              echo "5"
            else
              echo "3"
            fi
            ;;
          "get deployment"*)
            return 0
            ;;
          *)
            return 0
            ;;
        esac
        ;;
      "get hpa"*)
        return 1
        ;;
      "rollout status"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../set_desired_instance_count"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Namespace: default-namespace"
  assert_contains "$output" "🔍 Looking for deployment 'd-scope-123-deploy-456' in namespace 'default-namespace'..."
}
