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
  unset DNS_TYPE INGRESS_FILE OUTPUT_DIR
}

render_ingress() {
  cat > "$1" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k-8-s-my-app-123-internet-facing
EOF
}

render_httproute() {
  cat > "$1" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: k-8-s-my-app-123-internet-facing
spec:
  parentRefs:
    - kind: Gateway
      name: gateway-public
EOF
}

# =============================================================================
# Rendered Kind Routing Tests
# =============================================================================
@test "verify_networking_reconciliation: shows start message and routes a rendered Ingress" {
  export INGRESS_FILE="$BATS_TEST_TMPDIR/ingress.yaml"
  render_ingress "$INGRESS_FILE"

  local bg_context='{"scope":{"slug":"my-app","domain":"app.example.com"},"deployment":{"strategy":"blue_green"}}'

  run bash -c "
    kubectl() { return 0; }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL'
    export ALB_RECONCILIATION_ENABLED='false' REGION='$REGION'
    export CONTEXT='$bg_context'
    export INGRESS_FILE='$INGRESS_FILE'
    source '$BATS_TEST_DIRNAME/../verify_networking_reconciliation'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Verifying networking reconciliation for kind: Ingress"
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "⚠️ Skipping ALB verification (ALB access needed for blue-green traffic validation)"
}

@test "verify_networking_reconciliation: routes a rendered HTTPRoute" {
  export INGRESS_FILE="$BATS_TEST_TMPDIR/httproute.yaml"
  render_httproute "$INGRESS_FILE"

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
  assert_contains "$output" "🔍 Verifying networking reconciliation for kind: HTTPRoute"
  assert_contains "$output" "🔍 Verifying HTTPRoute reconciliation..."
  assert_contains "$output" "✅ HTTPRoute successfully reconciled"
}

@test "verify_networking_reconciliation: routes an HTTPRoute even when DNS is managed by Route53" {
  export INGRESS_FILE="$BATS_TEST_TMPDIR/httproute.yaml"
  render_httproute "$INGRESS_FILE"

  export DNS_TYPE="route53"
  export SCOPE_ID="123"
  export K8S_NAMESPACE="nullplatform"
  export INGRESS_VISIBILITY="internet-facing"
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
  assert_contains "$output" "🔍 Verifying networking reconciliation for kind: HTTPRoute"
  assert_contains "$output" "✅ HTTPRoute successfully reconciled"
  [[ "$output" != *"Failed to get ingress"* ]]
}

@test "verify_networking_reconciliation: falls back to the conventional manifest path" {
  export OUTPUT_DIR="$BATS_TEST_TMPDIR"
  export SCOPE_ID="123"
  export DEPLOYMENT_ID="456"
  render_httproute "$OUTPUT_DIR/ingress-123-456.yaml"

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
  assert_contains "$output" "🔍 Verifying networking reconciliation for kind: HTTPRoute"
}

@test "verify_networking_reconciliation: skips when no manifest was rendered" {
  export INGRESS_FILE="$BATS_TEST_TMPDIR/missing.yaml"

  run bash "$BATS_TEST_DIRNAME/../verify_networking_reconciliation"

  [ "$status" -eq 0 ]

  assert_contains "$output" "🔍 Verifying networking reconciliation for kind: unknown"
  assert_contains "$output" "⚠️ Networking reconciliation not available for kind: unknown, skipping"
}

@test "verify_networking_reconciliation: skips for an unsupported kind" {
  export INGRESS_FILE="$BATS_TEST_TMPDIR/other.yaml"
  printf 'apiVersion: v1\nkind: Service\n' > "$INGRESS_FILE"

  run bash "$BATS_TEST_DIRNAME/../verify_networking_reconciliation"

  [ "$status" -eq 0 ]

  assert_contains "$output" "🔍 Verifying networking reconciliation for kind: Service"
  assert_contains "$output" "⚠️ Networking reconciliation not available for kind: Service, skipping"
}
