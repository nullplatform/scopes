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

  kubectl() {
    echo "kubectl $*"
    case "$1" in
      get)
        return 0  # Ingress exists
        ;;
      patch)
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
@test "delete_ingress_finalizer: removes finalizer when ingress exists" {
  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking for ingress finalizers to remove..."
  assert_contains "$output" "📋 Ingress name: k-8-s-my-app-123-internet-facing"
  assert_contains "$output" "📝 Removing finalizers from ingress k-8-s-my-app-123-internet-facing..."
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-internet-facing"
}

@test "delete_ingress_finalizer: targets the resolved ingress name from context, not a constructed one" {
  export CONTEXT='{
    "scope": {"slug": "my-app", "id": 123},
    "ingress_visibility": "internet-facing",
    "names": {"scope_ingress": "checkout-api-production-123456"}
  }'

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Ingress name: checkout-api-production-123456"
  assert_contains "$output" "✅ Finalizers removed from ingress checkout-api-production-123456"
}

# =============================================================================
# Ingress Not Found Case
# =============================================================================
@test "delete_ingress_finalizer: skips when ingress not found" {
  kubectl() {
    case "$1" in
      get)
        return 1  # Ingress does not exist
        ;;
    esac
    return 0
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking for ingress finalizers to remove..."
  assert_contains "$output" "📋 Ingress k-8-s-my-app-123-internet-facing not found, skipping finalizer removal"
}

setup_additional_ports() {
  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "id": 123,
      "capabilities": {
        "additional_ports": [
          {"port": 8081, "type": "HTTP", "ingress_name": "k-8-s-my-app-123-http-8081-internet-facing"},
          {"port": 9090, "type": "GRPC", "ingress_name": "k-8-s-my-app-123-grpc-9090-internet-facing"}
        ]
      }
    },
    "ingress_visibility": "internet-facing",
    "names": {"scope_ingress": "k-8-s-my-app-123-internet-facing"}
  }'
  export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  export EXISTING_INGRESSES="k-8-s-my-app-123-internet-facing k-8-s-my-app-123-http-8081-internet-facing k-8-s-my-app-123-grpc-9090-internet-facing"
  export FAILING_PATCH=""

  kubectl() {
    echo "kubectl $*" >> "$KUBECTL_LOG"
    case "$1" in
      get)
        [[ " $EXISTING_INGRESSES " == *" $3 "* ]]
        return
        ;;
      patch)
        [ "$3" != "$FAILING_PATCH" ]
        return
        ;;
    esac
    return 0
  }
  export -f kubectl
}

@test "delete_ingress_finalizer: removes finalizers from the HTTP and GRPC additional port ingresses" {
  setup_additional_ports

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking for ingress finalizers to remove..."
  assert_contains "$output" "📋 Ingress name: k-8-s-my-app-123-internet-facing"
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-internet-facing"
  assert_contains "$output" "📋 Ingress name: k-8-s-my-app-123-http-8081-internet-facing"
  assert_contains "$output" "📝 Removing finalizers from ingress k-8-s-my-app-123-http-8081-internet-facing..."
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-http-8081-internet-facing"
  assert_contains "$output" "📋 Ingress name: k-8-s-my-app-123-grpc-9090-internet-facing"
  assert_contains "$output" "📝 Removing finalizers from ingress k-8-s-my-app-123-grpc-9090-internet-facing..."
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-grpc-9090-internet-facing"
  assert_contains "$(cat "$KUBECTL_LOG")" 'kubectl patch ingress k-8-s-my-app-123-internet-facing -n test-namespace -p {"metadata":{"finalizers":[]}} --type=merge'
  assert_contains "$(cat "$KUBECTL_LOG")" 'kubectl patch ingress k-8-s-my-app-123-http-8081-internet-facing -n test-namespace -p {"metadata":{"finalizers":[]}} --type=merge'
  assert_contains "$(cat "$KUBECTL_LOG")" 'kubectl patch ingress k-8-s-my-app-123-grpc-9090-internet-facing -n test-namespace -p {"metadata":{"finalizers":[]}} --type=merge'
}

@test "delete_ingress_finalizer: skips a missing additional port ingress and still patches the rest" {
  setup_additional_ports
  export EXISTING_INGRESSES="k-8-s-my-app-123-internet-facing k-8-s-my-app-123-grpc-9090-internet-facing"

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Ingress k-8-s-my-app-123-http-8081-internet-facing not found, skipping finalizer removal"
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-internet-facing"
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-grpc-9090-internet-facing"
  [ "$(grep -c '^kubectl patch' "$KUBECTL_LOG")" -eq 2 ]
}

@test "delete_ingress_finalizer: fails when patching an additional port ingress fails" {
  setup_additional_ports
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

@test "delete_ingress_finalizer: fails when the context cannot be read" {
  setup_additional_ports
  export CONTEXT='not json'

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to read the ingress names from the deployment context"
  [ ! -s "$KUBECTL_LOG" ]
}

@test "delete_ingress_finalizer: ignores an additional port without an ingress name" {
  setup_additional_ports
  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "id": 123,
      "capabilities": {
        "additional_ports": [
          {"port": 8081, "type": "HTTP"}
        ]
      }
    },
    "names": {"scope_ingress": "k-8-s-my-app-123-internet-facing"}
  }'

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-internet-facing"
  [ "$(grep -c '^kubectl get' "$KUBECTL_LOG")" -eq 1 ]
  [ "$(grep -c 'null' "$KUBECTL_LOG")" -eq 0 ]
}
