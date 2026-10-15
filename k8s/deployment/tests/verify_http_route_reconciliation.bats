#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/verify_http_route_reconciliation - HTTPRoute verify
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"
  export INGRESS_VISIBILITY="internet-facing"
  export MAX_WAIT_SECONDS=1
  export CHECK_INTERVAL=0
  export HTTPROUTE_FIXTURE="$BATS_TEST_TMPDIR/httproute.json"

  export CONTEXT='{
    "scope": {
      "slug": "my-app"
    },
    "names": {
      "scope_ingress": "k-8-s-my-app-scope-123-internet-facing"
    }
  }'

  export ACCEPTED='{"type":"Accepted","status":"True","reason":"Accepted","message":"Route accepted"}'
  export RESOLVED='{"type":"ResolvedRefs","status":"True","reason":"ResolvedRefs","message":"Refs resolved"}'

  for helper in np_scope_step_begin np_scope_step_end np_scope_step_timeout np_scope_wait_heartbeat np_scope_explain np_scope_output np_scope_consumes np_scope_progress; do
    eval "$helper() { :; }"
    export -f "$helper"
  done
}

teardown() {
  unset CONTEXT
}

# Usage: httproute '<parentRefs json>' '<status.parents json>'
httproute() {
  jq -n --argjson refs "$1" --argjson parents "$2" '{spec: {parentRefs: $refs}, status: {parents: $parents}}' > "$HTTPROUTE_FIXTURE"
}

# Usage: parent <name> <namespace> <condition json>...
parent() {
  local name="$1" namespace="$2"
  shift 2
  jq -nc --arg name "$name" --arg namespace "$namespace" --argjson conditions "$(printf '%s\n' "$@" | jq -sc .)" \
    '{parentRef: {group: "gateway.networking.k8s.io", kind: "Gateway", name: $name, namespace: $namespace}, controllerName: "istio.io/gateway-controller", conditions: $conditions}'
}

ref() {
  jq -nc --arg name "$1" --arg namespace "$2" '{group: "gateway.networking.k8s.io", kind: "Gateway", name: $name, namespace: $namespace}'
}

single_gateway() {
  httproute "[$(ref gateway-public gateways)]" "[$(parent gateway-public gateways "$@")]"
}

mock_tracing() {
  export TRACE_LOG="$BATS_TEST_TMPDIR/trace.log"
  for helper in np_scope_step_begin np_scope_step_end np_scope_step_timeout np_scope_wait_heartbeat np_scope_explain np_scope_output np_scope_consumes np_scope_progress; do
    eval "$helper() { echo \"$helper \$*\" >> \"\$TRACE_LOG\"; }"
    export -f "$helper"
  done
}

run_verify() {
  run bash -c "
    kubectl() { cat '$HTTPROUTE_FIXTURE'; return 0; }
    export -f kubectl
    source '$BATS_TEST_DIRNAME/../verify_http_route_reconciliation'
  "
}

# =============================================================================
# Success Case
# =============================================================================
@test "verify_http_route_reconciliation: succeeds with correct logging" {
  single_gateway "$ACCEPTED" "$RESOLVED"

  run_verify

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "📋 HTTPRoute: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s"
  assert_contains "$output" "✅ HTTPRoute successfully reconciled (Accepted: True, ResolvedRefs: True)"
  assert_contains "$output" "✅ Gateways: gateways/gateway-public"
}

@test "verify_http_route_reconciliation: targets the resolved ingress name from context, not a constructed one" {
  export CONTEXT='{
    "scope": {"slug": "my-app"},
    "names": {"scope_ingress": "checkout-api-production-123456"}
  }'
  single_gateway "$ACCEPTED" "$RESOLVED"

  run_verify

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 HTTPRoute: checkout-api-production-123456 | Namespace: test-namespace | Timeout: 1s"
}

@test "verify_http_route_reconciliation: succeeds when every gateway accepted and resolved the route" {
  httproute "[$(ref gateway-public gateways), $(ref partners edge)]" \
    "[$(parent partners edge "$ACCEPTED" "$RESOLVED"), $(parent gateway-public gateways "$ACCEPTED" "$RESOLVED")]"

  run_verify

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ HTTPRoute successfully reconciled (Accepted: True, ResolvedRefs: True)"
  assert_contains "$output" "✅ Gateways: gateways/gateway-public, edge/partners"
}

@test "verify_http_route_reconciliation: a parentRef without namespace is matched in the route namespace" {
  httproute '[{"name":"local-gw"}]' '[{"parentRef":{"name":"local-gw"},"conditions":['"$ACCEPTED"','"$RESOLVED"']}]'

  run_verify

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Gateways: test-namespace/local-gw"
}

# =============================================================================
# Error Cases
# =============================================================================
@test "verify_http_route_reconciliation: fails with full troubleshooting on certificate error" {
  single_gateway '{"type":"Accepted","status":"False","reason":"CertificateError","message":"TLS secret not found"}' "$RESOLVED"

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "❌ HTTPRoute failed to reconcile on gateway gateways/gateway-public"
  assert_contains "$output" "❌ Certificate/TLS error detected"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- TLS secret does not exist in namespace test-namespace"
  assert_contains "$output" "- Certificate is invalid or expired"
  assert_contains "$output" "- Gateway references incorrect certificate secret"
  assert_contains "$output" "- Accepted: CertificateError - TLS secret not found"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Verify TLS secret: kubectl get secret -n test-namespace | grep tls"
  assert_contains "$output" "- Check certificate validity"
  assert_contains "$output" "- Ensure Gateway references the correct secret"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting on backend error" {
  single_gateway "$ACCEPTED" '{"type":"ResolvedRefs","status":"False","reason":"BackendNotFound","message":"service my-svc not found"}'

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "❌ HTTPRoute failed to reconcile on gateway gateways/gateway-public"
  assert_contains "$output" "❌ Backend service error detected"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Referenced service does not exist"
  assert_contains "$output" "- Service name is misspelled in HTTPRoute"
  assert_contains "$output" "- Message: service my-svc not found"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- List services: kubectl get svc -n test-namespace"
  assert_contains "$output" "- Verify backend service name in HTTPRoute"
  assert_contains "$output" "- Ensure service has ready endpoints"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting when not accepted" {
  single_gateway '{"type":"Accepted","status":"False","reason":"NotAccepted","message":"Gateway not found"}' "$RESOLVED"

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "❌ HTTPRoute failed to reconcile on gateway gateways/gateway-public"
  assert_contains "$output" "❌ HTTPRoute not accepted by Gateway"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Reason: NotAccepted"
  assert_contains "$output" "- Message: Gateway not found"
  assert_contains "$output" "📋 All conditions:"
  assert_contains "$output" "   - Accepted: False (NotAccepted) - Gateway not found"
  assert_contains "$output" "   - ResolvedRefs: True (ResolvedRefs) - Refs resolved"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Check Gateway configuration"
  assert_contains "$output" "- Verify the gateway gateways/gateway-public exists and allows routes from namespace test-namespace"
  assert_contains "$output" "- Verify HTTPRoute spec matches Gateway requirements"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting when refs not resolved" {
  single_gateway "$ACCEPTED" '{"type":"ResolvedRefs","status":"False","reason":"InvalidBackend","message":"Invalid backend port"}'

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "❌ HTTPRoute failed to reconcile on gateway gateways/gateway-public"
  assert_contains "$output" "❌ HTTPRoute references could not be resolved"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Reason: InvalidBackend"
  assert_contains "$output" "- Message: Invalid backend port"
  assert_contains "$output" "📋 All conditions:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Verify all referenced services exist"
  assert_contains "$output" "- Check backend service ports match"
}

@test "verify_http_route_reconciliation: fails when an additional gateway rejects the route while the main one accepts it" {
  httproute "[$(ref gateway-public gateways), $(ref partners edge)]" \
    "[$(parent gateway-public gateways "$ACCEPTED" "$RESOLVED"), $(parent partners edge '{"type":"Accepted","status":"False","reason":"NotAllowedByListeners","message":"No listener allows routes from test-namespace"}' "$RESOLVED")]"

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ HTTPRoute failed to reconcile on gateway edge/partners"
  assert_contains "$output" "❌ HTTPRoute not accepted by Gateway"
  assert_contains "$output" "- Reason: NotAllowedByListeners"
  assert_contains "$output" "- Message: No listener allows routes from test-namespace"
  [[ "$output" != *"successfully reconciled"* ]] || false
}

@test "verify_http_route_reconciliation: does not succeed while a gateway has not reported status" {
  export CHECK_INTERVAL=1
  httproute "[$(ref gateway-public gateways), $(ref partners edge)]" \
    "[$(parent gateway-public gateways "$ACCEPTED" "$RESOLVED")]"

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "📝 HTTPRoute reconciling, waiting for gateways: edge/partners (0s/1s)"
  assert_contains "$output" "❌ Timeout waiting for HTTPRoute reconciliation after 1s"
  assert_contains "$output" "   - Gateway gateways/gateway-public:"
  assert_contains "$output" "     - Accepted: True (Accepted) - Route accepted"
  assert_contains "$output" "   - Gateway edge/partners:"
  assert_contains "$output" "     - no status reported"
  [[ "$output" != *"successfully reconciled"* ]] || false
}

@test "verify_http_route_reconciliation: does not succeed while a gateway has not resolved refs" {
  export CHECK_INTERVAL=1
  httproute "[$(ref gateway-public gateways), $(ref partners edge)]" \
    "[$(parent gateway-public gateways "$ACCEPTED" "$RESOLVED"), $(parent partners edge "$ACCEPTED")]"

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "📝 HTTPRoute reconciling, waiting for gateways: edge/partners (0s/1s)"
  assert_contains "$output" "❌ Timeout waiting for HTTPRoute reconciliation after 1s"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting on timeout" {
  export CHECK_INTERVAL=1
  httproute '[]' '[]'

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "📝 HTTPRoute pending sync (no parent status yet)... (0s/1s)"
  assert_contains "$output" "❌ Timeout waiting for HTTPRoute reconciliation after 1s"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Gateway controller is not running"
  assert_contains "$output" "- A referenced gateway does not exist or is not managed by the controller"
  assert_contains "$output" "- Network policies blocking reconciliation"
  assert_contains "$output" "- Resource constraints on controller"
  assert_contains "$output" "📋 Current conditions:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Check Gateway controller logs"
  assert_contains "$output" "- Verify Gateway and Istio configuration"
}

@test "verify_http_route_reconciliation: traces every reconciled gateway" {
  mock_tracing
  httproute "[$(ref gateway-public gateways), $(ref partners edge)]" \
    "[$(parent gateway-public gateways "$ACCEPTED" "$RESOLVED"), $(parent partners edge "$ACCEPTED" "$RESOLVED")]"

  run_verify

  [ "$status" -eq 0 ]
  assert_equal "$(cat "$TRACE_LOG")" 'np_scope_step_begin verify-httproute --title Verify HTTPRoute reconciliation (k-8-s-my-app-scope-123-internet-facing)
np_scope_wait_heartbeat httproute-reconciliation 0 1 pending
np_scope_output gateways [{"gateway":"gateways/gateway-public","accepted":"True","resolved_refs":"True"},{"gateway":"edge/partners","accepted":"True","resolved_refs":"True"}]
np_scope_consumes k8s-gateway:gateways/gateway-public
np_scope_consumes k8s-gateway:edge/partners
np_scope_step_end 0
np_scope_explain --title Verify networking --what HTTPRoute k-8-s-my-app-scope-123-internet-facing reconciled — DNS routing verified'
}

@test "verify_http_route_reconciliation: fails the trace step naming the gateway that rejected the route" {
  mock_tracing
  httproute "[$(ref gateway-public gateways), $(ref partners edge)]" \
    "[$(parent gateway-public gateways "$ACCEPTED" "$RESOLVED"), $(parent partners edge '{"type":"Accepted","status":"False","reason":"NotAllowedByListeners","message":"No listener allows routes from test-namespace"}' "$RESOLVED")]"

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$(cat "$TRACE_LOG")" 'np_scope_output gateways [{"gateway":"gateways/gateway-public","accepted":"True","resolved_refs":"True"},{"gateway":"edge/partners","accepted":"False","resolved_refs":"True"}]'
  assert_contains "$(cat "$TRACE_LOG")" "np_scope_step_end 1 HTTPRoute k-8-s-my-app-scope-123-internet-facing failed to reconcile on gateway edge/partners"
  [[ "$(cat "$TRACE_LOG")" != *"np_scope_consumes"* ]] || false
}

@test "verify_http_route_reconciliation: traces gateway progress while waiting and their status on timeout" {
  mock_tracing
  export CHECK_INTERVAL=1
  httproute "[$(ref gateway-public gateways), $(ref partners edge)]" \
    "[$(parent gateway-public gateways "$ACCEPTED" "$RESOLVED")]"

  run_verify

  [ "$status" -eq 1 ]
  assert_contains "$(cat "$TRACE_LOG")" "np_scope_progress 1 2 gateways"
  assert_contains "$(cat "$TRACE_LOG")" 'np_scope_output gateways [{"gateway":"gateways/gateway-public","accepted":"True","resolved_refs":"True"},{"gateway":"edge/partners","accepted":"Unknown","resolved_refs":"Unknown"}]'
  assert_contains "$(cat "$TRACE_LOG")" "np_scope_step_timeout HTTPRoute k-8-s-my-app-scope-123-internet-facing not reconciled after 1s"
}
