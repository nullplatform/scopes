#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/verify_networking_reconciliation - networking verify
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SERVICE_PATH="$PROJECT_ROOT/k8s"

  # Mock the sourced scripts
  export INGRESS_RECONCILIATION_CALLED="false"
  export HTTP_ROUTE_RECONCILIATION_CALLED="false"
}

teardown() {
  unset DNS_TYPE
}

# =============================================================================
# DNS Type Routing Tests
# =============================================================================
@test "verify_networking_reconciliation: shows start message and routes by DNS type" {
  export DNS_TYPE="route53"

  local bg_context='{"scope":{"slug":"my-app","domain":"app.example.com"},"deployment":{"strategy":"blue_green"}}'

  run bash -c "
    kubectl() { return 0; }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL'
    export ALB_RECONCILIATION_ENABLED='false' REGION='$REGION'
    export CONTEXT='$bg_context'
    source '$BATS_TEST_DIRNAME/../verify_networking_reconciliation'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Verifying networking reconciliation for DNS type: route53"
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "⚠️ Skipping ALB verification (ALB access needed for blue-green traffic validation)"
}

@test "verify_networking_reconciliation: verifies HTTPRoute for external_dns without managing DNS" {
  export DNS_TYPE="external_dns"
  export SCOPE_ID="123"
  export K8S_NAMESPACE="nullplatform"
  export INGRESS_VISIBILITY="public"
  export MAX_WAIT_SECONDS="10"
  export CHECK_INTERVAL="10"
  export CONTEXT='{"scope":{"slug":"my-app","id":"123","domain":"app.example.com"}}'

  run bash -c "
    kubectl() {
      echo '{\"status\":{\"parents\":[{\"conditions\":[{\"type\":\"Accepted\",\"status\":\"True\",\"reason\":\"Accepted\"},{\"type\":\"ResolvedRefs\",\"status\":\"True\",\"reason\":\"ResolvedRefs\"}]}]}}'
      return 0
    }
    export -f kubectl
    sleep() { return 0; }
    export -f sleep
    source '$BATS_TEST_DIRNAME/../verify_networking_reconciliation'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Verifying networking reconciliation for DNS type: external_dns"
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "✅ HTTPRoute successfully reconciled"
}

@test "verify_networking_reconciliation: skips for unsupported DNS types" {
  export DNS_TYPE="unknown"

  run bash "$BATS_TEST_DIRNAME/../verify_networking_reconciliation"

  [ "$status" -eq 0 ]

  assert_contains "$output" "🔍 Verifying networking reconciliation for DNS type: unknown"
  assert_contains "$output" "⚠️ Ingress reconciliation not available for DNS type: unknown, skipping"
}
