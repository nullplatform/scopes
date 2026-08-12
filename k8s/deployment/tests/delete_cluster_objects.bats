#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/delete_cluster_objects - cluster cleanup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

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
        # $* already starts with "delete" (that's $1), so prefix with just
        # "kubectl" — echoing "kubectl delete $*" would double the verb.
        echo "kubectl $*"
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
  local expected
  expected=$(cat <<'EOF'
🔍 Starting cluster objects cleanup...
📋 Strategy: Deleting blue (old) deployment, keeping green (new)
📋 Deployment to clean: deploy-old | Deployment to keep: deploy-new
📝 Deleting resources for deployment_id=deploy-old...
kubectl delete deployment,service,hpa,ingress,pdb,secret,configmap -l deployment_id=deploy-old -n test-namespace --cascade=foreground --wait=true
Deleted resources
✅ Resources deleted for deployment_id=deploy-old
🔍 Verifying cleanup for scope_id=scope-123 in namespace=test-namespace...
✨ Cluster cleanup completed successfully
📋 Only deployment_id=deploy-new remains for scope_id=scope-123
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Green Deployment Cleanup Tests
# =============================================================================
@test "delete_cluster_objects: deletes green deployment and displays correct logging" {
  export DEPLOYMENT="green"

  run bash "$BATS_TEST_DIRNAME/../delete_cluster_objects"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<'EOF'
🔍 Starting cluster objects cleanup...
📋 Strategy: Deleting green (new) deployment, keeping blue (old)
📋 Deployment to clean: deploy-new | Deployment to keep: deploy-old
📝 Deleting resources for deployment_id=deploy-new...
kubectl delete deployment,service,hpa,ingress,pdb,secret,configmap -l deployment_id=deploy-new -n test-namespace --cascade=foreground --wait=true
Deleted resources
✅ Resources deleted for deployment_id=deploy-new
🔍 Verifying cleanup for scope_id=scope-123 in namespace=test-namespace...
✨ Cluster cleanup completed successfully
📋 Only deployment_id=deploy-old remains for scope_id=scope-123
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'
🔍 Starting cluster objects cleanup...
📋 Strategy: Deleting blue (old) deployment, keeping green (new)
📋 Deployment to clean: deploy-old | Deployment to keep: deploy-new
📝 Deleting resources for deployment_id=deploy-old...
❌ Failed to delete resources for deployment_id=deploy-old
💡 Possible causes:
   - Resources may have finalizers preventing deletion
   - Network connectivity issues with Kubernetes API
   - Insufficient permissions to delete resources
🔧 How to fix:
   - Check for stuck finalizers: kubectl get all -l deployment_id=deploy-old -n test-namespace -o yaml | grep finalizers
   - Verify kubeconfig and cluster connectivity
   - Check RBAC permissions for the service account
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Orphaned Deployment Cleanup Tests
# =============================================================================
@test "delete_cluster_objects: cleans up orphaned deployments" {
  kubectl() {
    case "$1" in
      delete)
        # $* already starts with "delete" (that's $1), so prefix with just
        # "kubectl" — echoing "kubectl delete $*" would double the verb.
        echo "kubectl $*"
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
  local expected
  expected=$(cat <<'EOF'
🔍 Starting cluster objects cleanup...
📋 Strategy: Deleting blue (old) deployment, keeping green (new)
📋 Deployment to clean: deploy-old | Deployment to keep: deploy-new
📝 Deleting resources for deployment_id=deploy-old...
kubectl delete deployment,service,hpa,ingress,pdb,secret,configmap -l deployment_id=deploy-old -n test-namespace --cascade=foreground --wait=true
Deleted resources
✅ Resources deleted for deployment_id=deploy-old
🔍 Verifying cleanup for scope_id=scope-123 in namespace=test-namespace...
📝 Found orphaned deployment: deploy-orphan
📝 Deleting resources for deployment_id=deploy-orphan...
kubectl delete deployment,service,hpa,ingress,pdb,secret,configmap -l deployment_id=deploy-orphan -n test-namespace --cascade=foreground --wait=true
Deleted resources
✅ Resources deleted for deployment_id=deploy-orphan
✅ Cleaned up 1 orphaned deployment(s)
✨ Cluster cleanup completed successfully
📋 Only deployment_id=deploy-new remains for scope_id=scope-123
EOF
)
  assert_equal "$output" "$expected"
}

