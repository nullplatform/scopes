#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/resume_autoscaling - restore HPA from paused state
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
}

teardown() {
  unset -f kubectl
}

# =============================================================================
# HPA Not Found
# =============================================================================
@test "resume_autoscaling: fails when HPA does not exist" {
  kubectl() {
    case "$*" in
      "get hpa"*)
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../resume_autoscaling"

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Looking for HPA 'hpa-d-scope-123-deploy-456' in namespace 'provider-namespace'..."
  assert_contains "$output" "❌ HPA 'hpa-d-scope-123-deploy-456' not found in namespace 'provider-namespace'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The HPA may not exist or autoscaling is not configured for this deployment"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify the HPA exists: kubectl get hpa -n provider-namespace"
  assert_contains "$output" "• Check that autoscaling is configured for scope scope-123"
}

# =============================================================================
# HPA Already Active (idempotent)
# =============================================================================
@test "resume_autoscaling: succeeds when HPA is already active (empty annotation)" {
  kubectl() {
    case "$*" in
      "get hpa"*"-n provider-namespace"*)
        if [[ "$*" == *"-o jsonpath"* ]]; then
          echo ""
        else
          return 0
        fi
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../resume_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ HPA 'hpa-d-scope-123-deploy-456' is already active, no action needed"
}

@test "resume_autoscaling: succeeds when hpa is not paused" {
  kubectl() {
    case "$*" in
      "get hpa"*"-n provider-namespace"*)
        if [[ "$*" == *"-o jsonpath"* ]]; then
          echo "null"
        else
          return 0
        fi
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../resume_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ HPA 'hpa-d-scope-123-deploy-456' is already active, no action needed"
}

# =============================================================================
# Successful Resume Flow
# =============================================================================
@test "resume_autoscaling: complete successful resume flow" {
  kubectl() {
    case "$*" in
      "get hpa"*"-n provider-namespace"*)
        if [[ "$*" == *"-o jsonpath"* ]]; then
          echo '{"originalMinReplicas":3,"originalMaxReplicas":15,"pausedAt":"2024-06-15T10:30:00Z"}'
        else
          return 0
        fi
        ;;
      "patch hpa"*)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../resume_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Looking for HPA 'hpa-d-scope-123-deploy-456' in namespace 'provider-namespace'..."
  assert_contains "$output" "📋 Found paused HPA configuration:"
  assert_contains "$output" "   Original min replicas: 3"
  assert_contains "$output" "   Original max replicas: 15"
  assert_contains "$output" "   Paused at: 2024-06-15T10:30:00Z"
  assert_contains "$output" "📝 Resuming autoscaling..."
  assert_contains "$output" "✅ Autoscaling resumed successfully"
  assert_contains "$output" "   HPA: hpa-d-scope-123-deploy-456"
  assert_contains "$output" "   Namespace: provider-namespace"
  assert_contains "$output" "   Min replicas: 3"
  assert_contains "$output" "   Max replicas: 15"
}

@test "resume_autoscaling: removes paused annotation" {
  kubectl() {
    case "$*" in
      "get hpa"*"-n provider-namespace"*)
        if [[ "$*" == *"-o jsonpath"* ]]; then
          echo '{"originalMinReplicas":2,"originalMaxReplicas":10,"pausedAt":"2024-01-01T00:00:00Z"}'
        else
          return 0
        fi
        ;;
      "patch hpa"*)
        if [[ "$*" == *"null"* ]]; then
          return 0
        fi
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../resume_autoscaling"

  [ "$status" -eq 0 ]
}

# =============================================================================
# Namespace Resolution Tests
# =============================================================================
@test "resume_autoscaling: uses namespace from provider" {
  kubectl() {
    case "$*" in
      *"-n provider-namespace"*)
        if [[ "$*" == *"-o jsonpath"* ]]; then
          echo '{"originalMinReplicas":2,"originalMaxReplicas":10,"pausedAt":"2024-01-01T00:00:00Z"}'
        else
          return 0
        fi
        ;;
      *)
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../resume_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Looking for HPA 'hpa-d-scope-123-deploy-456' in namespace 'provider-namespace'..."
  assert_contains "$output" "   Namespace: provider-namespace"
}

@test "resume_autoscaling: falls back to default namespace" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.namespace)')

  kubectl() {
    case "$*" in
      *"-n default-namespace"*)
        if [[ "$*" == *"-o jsonpath"* ]]; then
          echo '{"originalMinReplicas":2,"originalMaxReplicas":10,"pausedAt":"2024-01-01T00:00:00Z"}'
        else
          return 0
        fi
        ;;
      *)
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../resume_autoscaling"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Looking for HPA 'hpa-d-scope-123-deploy-456' in namespace 'default-namespace'..."
  assert_contains "$output" "   Namespace: default-namespace"
}
