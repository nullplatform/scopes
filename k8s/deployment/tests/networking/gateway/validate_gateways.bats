#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/networking/gateway/validate_gateways
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCRIPT="$PROJECT_ROOT/k8s/deployment/networking/gateway/validate_gateways"
  export SCOPE_VISIBILITY="private"
  export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  export MISSING_GATEWAYS_FIXTURE=""
  export FORBIDDEN_GATEWAYS_FIXTURE=""
  export INVALID_ADDITIONAL_GATEWAYS=""

  export CONTEXT='{
    "gateway_name": "gateway-internal",
    "gateways": [
      {"name": "gateway-internal", "namespace": "gateways"},
      {"name": "partners", "namespace": "edge"}
    ]
  }'

  kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    local name="$3" namespace="$5"
    if [[ " $MISSING_GATEWAYS_FIXTURE " == *" $namespace/$name "* ]]; then
      echo "Error from server (NotFound): gateways.gateway.networking.k8s.io \"$name\" not found" >&2
      return 1
    fi
    if [[ " $FORBIDDEN_GATEWAYS_FIXTURE " == *" $namespace/$name "* ]]; then
      echo "Error from server (Forbidden): gateways.gateway.networking.k8s.io \"$name\" is forbidden" >&2
      return 1
    fi
    echo "gateway.gateway.networking.k8s.io/$name"
  }
  export -f kubectl
}

@test "validate_gateways: succeeds when every gateway exists" {
  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Validating gateways referenced by the HTTPRoute..."
  assert_contains "$output" "✅ Gateway 'gateways/gateway-internal' exists"
  assert_contains "$output" "✅ Gateway 'edge/partners' exists"
  assert_contains "$output" "✅ All gateways exist: gateways/gateway-internal, edge/partners"
  assert_equal "$(cat "$KUBECTL_LOG")" "get gateway gateway-internal -n gateways -o name
get gateway partners -n edge -o name"
}

@test "validate_gateways: fails listing every missing gateway" {
  export MISSING_GATEWAYS_FIXTURE="gateways/gateway-internal edge/partners"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Validating gateways referenced by the HTTPRoute..."
  assert_contains "$output" "❌ Gateways not found: gateways/gateway-internal edge/partners"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - The gateway name or namespace is misspelled in the scope-configurations or container-orchestration provider"
  assert_contains "$output" "   - The gateway was not created in the cluster yet"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   - List the gateways in the cluster: kubectl get gateways -A"
  assert_contains "$output" "   - Fix the gateway names and namespaces configured for private scopes"
}

@test "validate_gateways: fails when only an additional gateway is missing" {
  export MISSING_GATEWAYS_FIXTURE="edge/partners"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "✅ Gateway 'gateways/gateway-internal' exists"
  assert_contains "$output" "❌ Gateways not found: edge/partners"
}

@test "validate_gateways: reports an API error separately from a missing gateway" {
  export FORBIDDEN_GATEWAYS_FIXTURE="edge/partners"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not check gateway 'edge/partners': Error from server (Forbidden): gateways.gateway.networking.k8s.io \"partners\" is forbidden"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - The cluster API server is unreachable"
  assert_contains "$output" "   - RBAC denies reading gateways in namespace 'edge'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   - Verify cluster connectivity and RBAC: kubectl auth can-i get gateways -n edge"
  [[ "$output" != *"Gateways not found"* ]] || false
}

@test "validate_gateways: without gateways in the context validates gateway_name in the gateways namespace" {
  export CONTEXT='{"gateway_name": "gateway-internal"}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ All gateways exist: gateways/gateway-internal"
  assert_equal "$(cat "$KUBECTL_LOG")" "get gateway gateway-internal -n gateways -o name"
}

@test "validate_gateways: fails on invalid additional gateways before looking up any gateway" {
  export INVALID_ADDITIONAL_GATEWAYS='[{"namespace": "edge"}]'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Validating gateways referenced by the HTTPRoute..."
  assert_contains "$output" '❌ Invalid additional gateways for private scopes: [{"namespace": "edge"}]'
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   - additional_private_gateways is not a list of objects with a valid Kubernetes 'name' and optional 'namespace'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" '   - Set it as a list like [{"name": "my-gateway", "namespace": "gateways"}] in the scope-configurations or container-orchestration provider'
  [ ! -f "$KUBECTL_LOG" ]
}

@test "validate_gateways: does not leak its variables into the sourcing shell" {
  source "$SCRIPT"

  [ -z "${gateway_name:-}" ]
  [ -z "${missing_gateways:-}" ]
}
