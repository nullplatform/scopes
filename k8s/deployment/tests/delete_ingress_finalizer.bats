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


# =============================================================================
# Additional Ports Case
# =============================================================================
@test "delete_ingress_finalizer: removes finalizers from every additional port ingress" {
  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "id": 123,
      "capabilities": {
        "additional_ports": [
          {"port": 9010, "type": "GRPC", "ingress_name": "k-8-s-my-app-123-grpc-9010-internet-facing"},
          {"port": 8081, "type": "HTTP", "ingress_name": "k-8-s-my-app-123-http-8081-internet-facing"}
        ]
      }
    },
    "names": {"scope_ingress": "k-8-s-my-app-123-internet-facing"}
  }'

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl patch ingress k-8-s-my-app-123-internet-facing -n test-namespace"
  assert_contains "$output" "kubectl patch ingress k-8-s-my-app-123-grpc-9010-internet-facing -n test-namespace"
  assert_contains "$output" "kubectl patch ingress k-8-s-my-app-123-http-8081-internet-facing -n test-namespace"
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-grpc-9010-internet-facing"
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-http-8081-internet-facing"
}

@test "delete_ingress_finalizer: removes additional port finalizers when the main ingress is already gone" {
  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "id": 123,
      "capabilities": {
        "additional_ports": [
          {"port": 9010, "type": "GRPC", "ingress_name": "k-8-s-my-app-123-grpc-9010-internet-facing"}
        ]
      }
    },
    "names": {"scope_ingress": "k-8-s-my-app-123-internet-facing"}
  }'
  kubectl() {
    echo "kubectl $*"
    if [ "$1" = "get" ] && [ "$3" = "k-8-s-my-app-123-internet-facing" ]; then
      return 1
    fi
    return 0
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Ingress k-8-s-my-app-123-internet-facing not found, skipping finalizer removal"
  assert_contains "$output" "✅ Finalizers removed from ingress k-8-s-my-app-123-grpc-9010-internet-facing"
}

@test "delete_ingress_finalizer: only patches the main ingress when the scope has no additional ports" {
  run bash "$BATS_TEST_DIRNAME/../delete_ingress_finalizer"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c '^kubectl patch ingress')" -eq 1 ]
}
