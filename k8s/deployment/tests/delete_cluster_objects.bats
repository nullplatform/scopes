#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/delete_cluster_objects - cluster cleanup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-new"
  export DEPLOYMENT="blue"

  export CONTEXT='{
    "scope": {
      "current_active_deployment": "deploy-old"
    }
  }'

  kubectl() {
    case "$1" in
      delete)
        echo "kubectl delete $*"
        echo "Deleted resources"
        return 0
        ;;
      get)
        # Return empty list for cleanup verification
        echo ""
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
# Blue Deployment Cleanup Tests
# =============================================================================
@test "delete_cluster_objects: deletes blue deployment and displays correct logging" {
  export DEPLOYMENT="blue"

  run bash "$BATS_TEST_DIRNAME/../delete_cluster_objects"

  [ "$status" -eq 0 ]
  # Start message
  assert_contains "$output" "🔍 Starting cluster objects cleanup..."
  # Strategy message
  assert_contains "$output" "📋 Strategy: Deleting blue (old) deployment, keeping green (new)"
  # Debug info
  assert_contains "$output" "📋 Deployment to clean: deploy-old | Deployment to keep: deploy-new"
  # Delete action
  assert_contains "$output" "📝 Deleting resources for deployment_id=deploy-old..."
  assert_contains "$output" "✅ Resources deleted for deployment_id=deploy-old"
  # Verification
  assert_contains "$output" "🔍 Verifying cleanup for scope_id=scope-123 in namespace=test-namespace..."
  # Summary
  assert_contains "$output" "✨ Cluster cleanup completed successfully"
  assert_contains "$output" "📋 Only deployment_id=deploy-new remains for scope_id=scope-123"
}

# =============================================================================
# Green Deployment Cleanup Tests
# =============================================================================
@test "delete_cluster_objects: deletes green deployment and displays correct logging" {
  export DEPLOYMENT="green"

  run bash "$BATS_TEST_DIRNAME/../delete_cluster_objects"

  [ "$status" -eq 0 ]
  # Strategy message
  assert_contains "$output" "📋 Strategy: Deleting green (new) deployment, keeping blue (old)"
  # Debug info
  assert_contains "$output" "📋 Deployment to clean: deploy-new | Deployment to keep: deploy-old"
  # Delete action
  assert_contains "$output" "📝 Deleting resources for deployment_id=deploy-new..."
  assert_contains "$output" "✅ Resources deleted for deployment_id=deploy-new"
  # Summary
  assert_contains "$output" "📋 Only deployment_id=deploy-old remains for scope_id=scope-123"
}

# =============================================================================
# Resource Types Tests
# =============================================================================
@test "delete_cluster_objects: uses correct kubectl options" {
  run bash "$BATS_TEST_DIRNAME/../delete_cluster_objects"

  [ "$status" -eq 0 ]
  # Check the kubectl delete command includes all resource types
  assert_contains "$output" "deployment,service,hpa,ingress,pdb,secret,configmap"
  assert_contains "$output" "--cascade=foreground"
  assert_contains "$output" "--wait=true"
}

# =============================================================================
# Error Handling Tests
# =============================================================================
@test "delete_cluster_objects: displays error with troubleshooting on kubectl failure" {
  kubectl() {
    case "$1" in
      delete)
        return 1
        ;;
      get)
        echo ""
        return 0
        ;;
    esac
    return 0
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../delete_cluster_objects"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to delete resources for deployment_id=deploy-old"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Resources may have finalizers preventing deletion"
  assert_contains "$output" "Network connectivity issues with Kubernetes API"
  assert_contains "$output" "Insufficient permissions to delete resources"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check for stuck finalizers"
  assert_contains "$output" "Verify kubeconfig and cluster connectivity"
  assert_contains "$output" "Check RBAC permissions for the service account"
}

# =============================================================================
# Orphaned Deployment Cleanup Tests
# =============================================================================
@test "delete_cluster_objects: cleans up orphaned deployments" {
  kubectl() {
    case "$1" in
      delete)
        echo "kubectl delete $*"
        echo "Deleted resources"
        return 0
        ;;
      get)
        # Return list with orphaned deployment
        echo "deploy-new"
        echo "deploy-orphan"
        return 0
        ;;
    esac
    return 0
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../delete_cluster_objects"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Found orphaned deployment: deploy-orphan"
  assert_contains "$output" "✅ Cleaned up 1 orphaned deployment(s)"
}

