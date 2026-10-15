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

  for helper in np_scope_step_begin np_scope_step_end np_scope_explain np_scope_input np_scope_output np_scope_consumes; do
    eval "$helper() { :; }"
    export -f "$helper"
  done
}

run_with_logging() {
  run "$BASH" -c "
    ( source '$PROJECT_ROOT/k8s/logging'; source '$SCRIPT' )
    rc=\$?
    for event in \"\${NP_TRACE_DIR:-/nonexistent}\"/spool/*.json \"\${NP_TRACE_DIR:-/nonexistent}\"/failed/*.json; do
      [ -f \"\$event\" ] && cat \"\$event\" && echo
    done
    exit \$rc
  "
}

trace_platform_step() {
  export NP_TRACE="1|trace-9|deployment-42~configure-ingress@0.0"
  export NP_API_KEY="test-key"
  export NP_TRACE_DIR="$BATS_TEST_TMPDIR/nptrace"
  export NP_TRACE_BASE_URL="http://127.0.0.1:1"
  export NP_TRACE_AUTH_URL="http://127.0.0.1:1"
  export NP_TRACE_FLUSH_TIMEOUT=1
  export NP_TRACE_MAX_RETRIES=0
}

mock_tracing() {
  export TRACE_LOG="$BATS_TEST_TMPDIR/trace.log"
  for helper in np_scope_step_begin np_scope_step_end np_scope_explain np_scope_input np_scope_output np_scope_consumes; do
    eval "$helper() { echo \"$helper \$*\" >> \"\$TRACE_LOG\"; }"
    export -f "$helper"
  done
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

@test "validate_gateways: an untraced run with the real logging prints only the result" {
  run_with_logging

  [ "$status" -eq 0 ]
  assert_equal "$output" "✅ All gateways exist: gateways/gateway-internal, edge/partners"
}

@test "validate_gateways: a traced run reports the validation step and the gateways it consumes" {
  trace_platform_step

  run_with_logging

  [ "$status" -eq 0 ]
  echo "$output" | grep '"status":"completed"' | grep -q 'deployment-42~configure-ingress@0.0~validate-gateways@0.0'
  echo "$output" | grep '"edge.consumes"' | grep -q '"id":"k8s-gateway:gateways/gateway-internal"'
  echo "$output" | grep '"edge.consumes"' | grep -q '"id":"k8s-gateway:edge/partners"'
  echo "$output" | grep -q 'Validate gateways for private scope'
}

@test "validate_gateways: a traced run fails the validation step with the missing gateways" {
  trace_platform_step
  export MISSING_GATEWAYS_FIXTURE="edge/partners"

  run_with_logging

  [ "$status" -eq 1 ]
  echo "$output" | grep '"status":"failed"' | grep -q 'validate-gateways@0.0'
  echo "$output" | grep -q 'Gateways not found: edge/partners'
}

@test "validate_gateways: traces the validation step and every gateway it consumes" {
  mock_tracing

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_equal "$(cat "$TRACE_LOG")" 'np_scope_step_begin validate-gateways --title Validate gateways for private scope
np_scope_input gateways [{"name":"gateway-internal","namespace":"gateways"},{"name":"partners","namespace":"edge"}]
np_scope_consumes k8s-gateway:gateways/gateway-internal
np_scope_consumes k8s-gateway:edge/partners
np_scope_explain --title Validate gateways for private scope --what All gateways exist: gateways/gateway-internal, edge/partners
np_scope_step_end 0'
}
@test "validate_gateways: fails the trace step listing the missing gateways" {
  mock_tracing
  export MISSING_GATEWAYS_FIXTURE="gateways/gateway-internal edge/partners"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$(cat "$TRACE_LOG")" 'np_scope_output missing_gateways ["gateways/gateway-internal","edge/partners"]'
  assert_contains "$(cat "$TRACE_LOG")" "np_scope_step_end 1 Gateways not found: gateways/gateway-internal edge/partners"
  [[ "$(cat "$TRACE_LOG")" != *"np_scope_consumes"* ]] || false
}

@test "validate_gateways: fails the trace step when a gateway cannot be checked" {
  mock_tracing
  export FORBIDDEN_GATEWAYS_FIXTURE="edge/partners"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$(cat "$TRACE_LOG")" "np_scope_step_end 1 Could not check gateway edge/partners"
}

@test "validate_gateways: fails the trace step on invalid additional gateways" {
  mock_tracing
  export INVALID_ADDITIONAL_GATEWAYS='[{"namespace": "edge"}]'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_equal "$(cat "$TRACE_LOG")" "np_scope_step_begin validate-gateways --title Validate gateways for private scope
np_scope_step_end 1 Invalid additional_private_gateways"
}
