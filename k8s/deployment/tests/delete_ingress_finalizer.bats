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
    "ingress_visibility": "internet-facing"
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

