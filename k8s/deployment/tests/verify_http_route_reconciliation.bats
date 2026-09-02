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
  local expected
  expected=$(cat <<'EOF'
🔍 Verifying HTTPRoute reconciliation...
📋 HTTPRoute: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s
✅ HTTPRoute successfully reconciled (Accepted: True, ResolvedRefs: True)
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Error Cases
# =============================================================================
@test "verify_http_route_reconciliation: fails with full troubleshooting on certificate error" {
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"False","reason":"CertificateError","message":"TLS secret not found"},{"type":"ResolvedRefs","status":"True","reason":"ResolvedRefs","message":"Refs resolved"}]}]}}'

  [ "$status" -eq 1 ]
  local expected
  expected=$(cat <<'EOF'
🔍 Verifying HTTPRoute reconciliation...
📋 HTTPRoute: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s
❌ Certificate/TLS error detected
💡 Possible causes:
   - TLS secret does not exist in namespace test-namespace
   - Certificate is invalid or expired
   - Gateway references incorrect certificate secret
   - Accepted: CertificateError - TLS secret not found
🔧 How to fix:
   - Verify TLS secret: kubectl get secret -n test-namespace | grep tls
   - Check certificate validity
   - Ensure Gateway references the correct secret
EOF
)
  assert_equal "$output" "$expected"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting on backend error" {
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"True","reason":"Accepted","message":"Accepted"},{"type":"ResolvedRefs","status":"False","reason":"BackendNotFound","message":"service my-svc not found"}]}]}}'

  [ "$status" -eq 1 ]
  local expected
  expected=$(cat <<'EOF'
🔍 Verifying HTTPRoute reconciliation...
📋 HTTPRoute: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s
❌ Backend service error detected
💡 Possible causes:
   - Referenced service does not exist
   - Service name is misspelled in HTTPRoute
   - Message: service my-svc not found
🔧 How to fix:
   - List services: kubectl get svc -n test-namespace
   - Verify backend service name in HTTPRoute
   - Ensure service has ready endpoints
EOF
)
  assert_equal "$output" "$expected"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting when not accepted" {
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"False","reason":"NotAccepted","message":"Gateway not found"},{"type":"ResolvedRefs","status":"True","reason":"ResolvedRefs","message":"Refs resolved"}]}]}}'

  [ "$status" -eq 1 ]
  local expected
  expected=$(cat <<'EOF'
🔍 Verifying HTTPRoute reconciliation...
📋 HTTPRoute: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s
❌ HTTPRoute not accepted by Gateway
💡 Possible causes:
   - Reason: NotAccepted
   - Message: Gateway not found
📋 All conditions:
   - Accepted: False (NotAccepted) - Gateway not found
   - ResolvedRefs: True (ResolvedRefs) - Refs resolved
🔧 How to fix:
   - Check Gateway configuration
   - Verify HTTPRoute spec matches Gateway requirements
EOF
)
  assert_equal "$output" "$expected"
}

@test "verify_http_route_reconciliation: fails with full troubleshooting when refs not resolved" {
  run_with_mock '{"status":{"parents":[{"conditions":[{"type":"Accepted","status":"True","reason":"Accepted","message":"Accepted"},{"type":"ResolvedRefs","status":"False","reason":"InvalidBackend","message":"Invalid backend port"}]}]}}'

  [ "$status" -eq 1 ]
  local expected
  expected=$(cat <<'EOF'
🔍 Verifying HTTPRoute reconciliation...
📋 HTTPRoute: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s
❌ HTTPRoute references could not be resolved
💡 Possible causes:
   - Reason: InvalidBackend
   - Message: Invalid backend port
📋 All conditions:
   - Accepted: True (Accepted) - Accepted
   - ResolvedRefs: False (InvalidBackend) - Invalid backend port
🔧 How to fix:
   - Verify all referenced services exist
   - Check backend service ports match
EOF
)
  assert_equal "$output" "$expected"
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
  # Everything up to the dynamic "Current conditions" dump: the mock's empty
  # parents list makes the jq read on it fail, so its tool-error text (not a
  # product message) is deliberately excluded here.
  local expected
  expected=$(cat <<'EOF'
🔍 Verifying HTTPRoute reconciliation...
📋 HTTPRoute: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s
📝 HTTPRoute pending sync (no parent status yet)... (0s/1s)
❌ Timeout waiting for HTTPRoute reconciliation after 1s
💡 Possible causes:
   - Gateway controller is not running
   - Network policies blocking reconciliation
   - Resource constraints on controller
📋 Current conditions:
EOF
)
  assert_contains "$output" "$expected"

  local expected_fix
  expected_fix=$(cat <<'EOF'
🔧 How to fix:
   - Check Gateway controller logs
   - Verify Gateway and Istio configuration
EOF
)
  assert_contains "$output" "$expected_fix"
}
