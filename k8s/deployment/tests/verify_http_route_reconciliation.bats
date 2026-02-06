#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/verify_http_route_reconciliation - HTTPRoute verify
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"
  export INGRESS_VISIBILITY="internet-facing"
  export MAX_WAIT_SECONDS=1
  export CHECK_INTERVAL=0

  export CONTEXT='{
    "scope": {
      "slug": "my-app"
    }
  }'
}

teardown() {
  unset CONTEXT
}

# Helper to run script with mock kubectl
run_with_mock() {
  local mock_response="$1"
  run bash -c "
    kubectl() { echo '$mock_response'; return 0; }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../verify_http_route_reconciliation'
  "
}

# =============================================================================
# Success Case
# =============================================================================
@test "verify_http_route_reconciliation: succeeds with correct logging" {
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"True","reason":"Accepted","message":"Route accepted"},{"type":"ResolvedRefs","status":"True","reason":"ResolvedRefs","message":"Refs resolved"}]}]}}'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "📋 HTTPRoute: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s"
  assert_contains "$output" "✅ HTTPRoute successfully reconciled (Accepted: True, ResolvedRefs: True)"
}

# =============================================================================
# Error Cases
# =============================================================================
@test "verify_http_route_reconciliation: fails with full troubleshooting on certificate error" {
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"False","reason":"CertificateError","message":"TLS secret not found"},{"type":"ResolvedRefs","status":"True","reason":"ResolvedRefs","message":"Refs resolved"}]}]}}'

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
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
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"True","reason":"Accepted","message":"Accepted"},{"type":"ResolvedRefs","status":"False","reason":"BackendNotFound","message":"service my-svc not found"}]}]}}'

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
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
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"False","reason":"NotAccepted","message":"Gateway not found"},{"type":"ResolvedRefs","status":"True","reason":"ResolvedRefs","message":"Refs resolved"}]}]}}'

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "❌ HTTPRoute not accepted by Gateway"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Reason: NotAccepted"
  assert_contains "$output" "- Message: Gateway not found"
  assert_contains "$output" "📋 All conditions:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Check Gateway configuration"
  assert_contains "$output" "- Verify HTTPRoute spec matches Gateway requirements"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting when refs not resolved" {
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"True","reason":"Accepted","message":"Accepted"},{"type":"ResolvedRefs","status":"False","reason":"InvalidBackend","message":"Invalid backend port"}]}]}}'

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "❌ HTTPRoute references could not be resolved"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Reason: InvalidBackend"
  assert_contains "$output" "- Message: Invalid backend port"
  assert_contains "$output" "📋 All conditions:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Verify all referenced services exist"
  assert_contains "$output" "- Check backend service ports match"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting on timeout" {
  export CHECK_INTERVAL=1
  run bash -c "
    kubectl() { echo '{\"status\":{\"parents\":[]}}'; return 0; }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='1' CHECK_INTERVAL='1' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../verify_http_route_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Timeout waiting for HTTPRoute reconciliation after 1s"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Gateway controller is not running"
  assert_contains "$output" "- Network policies blocking reconciliation"
  assert_contains "$output" "- Resource constraints on controller"
  assert_contains "$output" "📋 Current conditions:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Check Gateway controller logs"
  assert_contains "$output" "- Verify Gateway and Istio configuration"
}
