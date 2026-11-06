#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/delete_ingress_finalizer - ingress finalizer removal
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export K8S_NAMESPACE="test-namespace"

  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "id": 123
    },
    "ingress_visibility": "internet-facing",
    "names": {
      "scope_ingress": "k-8-s-my-app-123-internet-facing"
    }
  }'

  export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  export SCOPE_INGRESSES="k-8-s-my-app-123-internet-facing
k-8-s-my-app-123-http-8081-internet-facing
k-8-s-my-app-123-grpc-9090-internet-facing"
  export LIST_FAILS="false"
  export FAILING_PATCH=""

  kubectl() {
    echo "kubectl $*" >> "$KUBECTL_LOG"
    case "$1" in
      get)
        if [ "$LIST_FAILS" = "true" ]; then
          echo "error: You must be logged in to the server (Unauthorized)" >&2
          return 1
        fi
        if [ -n "$SCOPE_INGRESSES" ]; then
          echo "$SCOPE_INGRESSES"
        fi
        ;;
      patch)
        if [ "$3" = "$FAILING_PATCH" ]; then
          echo "Error from server (NotFound): ingresses.networking.k8s.io \"$3\" not found" >&2
          return 1
        fi
        echo "ingress.networking.k8s.io/$3 patched"
        ;;
    esac
  }
  export -f kubectl
}

teardown() {
  unset CONTEXT
  unset -f kubectl
}

@test "delete_ingress_finalizer: removes finalizers from every ingress labeled with the scope id" {
  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking for ingress finalizers to remove..."
  assert_contains "$output" "📋 Looking for ingresses with labels nullplatform=true,scope_id=123"
  assert_contains "$output" "📝 Removing finalizers from ingress k-8-s-my-app-123-internet-facing..."
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-internet-facing"
  assert_contains "$output" "📝 Removing finalizers from ingress k-8-s-my-app-123-http-8081-internet-facing..."
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-http-8081-internet-facing"
  assert_contains "$output" "📝 Removing finalizers from ingress k-8-s-my-app-123-grpc-9090-internet-facing..."
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-grpc-9090-internet-facing"
  assert_contains "$(cat "$KUBECTL_LOG")" "kubectl get ingress -n test-namespace -l nullplatform=true,scope_id=123 -o jsonpath={range .items[*]}{.metadata.name}{\"\n\"}{end}"
  assert_contains "$(cat "$KUBECTL_LOG")" 'kubectl patch ingress k-8-s-my-app-123-internet-facing -n test-namespace -p {"metadata":{"finalizers":[]}} --type=merge'
  assert_contains "$(cat "$KUBECTL_LOG")" 'kubectl patch ingress k-8-s-my-app-123-http-8081-internet-facing -n test-namespace -p {"metadata":{"finalizers":[]}} --type=merge'
  assert_contains "$(cat "$KUBECTL_LOG")" 'kubectl patch ingress k-8-s-my-app-123-grpc-9090-internet-facing -n test-namespace -p {"metadata":{"finalizers":[]}} --type=merge'
  [ "$(grep -c '^kubectl patch' "$KUBECTL_LOG")" -eq 3 ]
}

@test "delete_ingress_finalizer: selects ingresses by the scope id from context" {
  export CONTEXT='{"scope": {"slug": "checkout-api", "id": 456789}}'
  export SCOPE_INGRESSES="checkout-api-production-456789"

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Looking for ingresses with labels nullplatform=true,scope_id=456789"
  assert_contains "$output" "✅ Finalizers removed from ingress checkout-api-production-456789"
}

@test "delete_ingress_finalizer: skips when the scope has no ingresses" {
  export SCOPE_INGRESSES=""

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking for ingress finalizers to remove..."
  assert_contains "$output" "📋 No ingresses found for scope 123, skipping finalizer removal"
  [ "$(grep -c '^kubectl patch' "$KUBECTL_LOG")" -eq 0 ]
}

@test "delete_ingress_finalizer: fails when the ingresses cannot be listed" {
  export LIST_FAILS="true"

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to list the ingresses of scope 123 in namespace test-namespace"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - The cluster is unreachable"
  assert_contains "$output" "   - Insufficient permissions to list ingress resources"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   - Verify access: kubectl get ingress -n test-namespace -l nullplatform=true,scope_id=123"
  assert_contains "$output" "   - Check RBAC permissions for listing ingress resources"
  [ "$(grep -c '^kubectl patch' "$KUBECTL_LOG")" -eq 0 ]
}

@test "delete_ingress_finalizer: fails when removing the finalizers of an ingress fails" {
  export FAILING_PATCH="k-8-s-my-app-123-grpc-9090-internet-facing"

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 1 ]
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-http-8081-internet-facing"
  assert_contains "$output" "❌ Failed to remove finalizers from ingress k-8-s-my-app-123-grpc-9090-internet-facing"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - Ingress was deleted while patching"
  assert_contains "$output" "   - Insufficient permissions to patch ingress"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   - Verify ingress still exists: kubectl get ingress k-8-s-my-app-123-grpc-9090-internet-facing -n test-namespace"
  assert_contains "$output" "   - Check RBAC permissions for patching ingress resources"
}

@test "delete_ingress_finalizer: fails without calling kubectl when the context has no scope id" {
  export CONTEXT='{"scope": {"slug": "my-app"}}'

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not read the scope id from the deployment context"
  [ ! -s "$KUBECTL_LOG" ]
}
