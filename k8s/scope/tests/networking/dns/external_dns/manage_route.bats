#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/dns/external_dns/manage_route
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export SCRIPT="$SERVICE_PATH/scope/networking/dns/external_dns/manage_route"

  # Default environment
  export GATEWAY_NAME="gw-public"
  export SCOPE_ID="scope-123"
  export SCOPE_DOMAIN="myapp.example.com"
  export K8S_NAMESPACE="test-ns"
  export CONTEXT='{"scope":{"slug":"my-scope"},"application":{"slug":"my-app"}}'
  export OUTPUT_DIR="$(mktemp -d)"

  # Mock kubectl - default: gateway returns IP
  kubectl() {
    case "$*" in
      *"get gateway"*)
        echo "10.0.0.1"
        ;;
      *"get service"*)
        echo "10.0.0.2"
        ;;
      *"delete dnsendpoint"*)
        echo "dnsendpoint deleted"
        ;;
    esac
  }
  export -f kubectl

  # Mock gomplate
  gomplate() {
    # Just copy template to output
    local outfile=""
    local infile=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --out) outfile="$2"; shift 2 ;;
        --file) infile="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "rendered: $infile" > "$outfile"
  }
  export -f gomplate
}

teardown() {
  rm -rf "$OUTPUT_DIR"
}

# =============================================================================
# CREATE: success with gateway IP
# =============================================================================
@test "manage_route: CREATE - full success flow with gateway IP" {
  export ACTION="CREATE"
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Building DNSEndpoint manifest for ExternalDNS..."
  assert_contains "$output" "📡 Getting IP for gateway: gw-public"
  assert_contains "$output" "✅ Gateway address: 10.0.0.1 (recordType: A)"
  assert_contains "$output" "📝 Building DNSEndpoint from template:"
  assert_contains "$output" "✅ DNSEndpoint manifest created:"
}

# =============================================================================
# CREATE: fallback to service IP
# =============================================================================
@test "manage_route: CREATE - falls back to service when gateway has no IP" {
  export ACTION="CREATE"
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  kubectl() {
    case "$*" in
      *"get gateway"*)
        echo ""
        ;;
      *"get service"*)
        echo "10.0.0.2"
        ;;
    esac
  }
  export -f kubectl

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  Gateway hostname not found, trying service fallback..."
  assert_contains "$output" "✅ Gateway address: 10.0.0.2 (recordType: A)"
}

# =============================================================================
# CREATE: no IP available - exits 0
# =============================================================================
@test "manage_route: CREATE - exits 0 when no IP available" {
  kubectl() { echo ""; }
  export -f kubectl

  export ACTION="CREATE"
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  Could not determine gateway IP address yet, DNSEndpoint will be created later"
}

# =============================================================================
# CREATE: template not found
# =============================================================================
@test "manage_route: CREATE - fails with error details when template not found" {
  export DNS_ENDPOINT_TEMPLATE="/nonexistent/template.yaml.tpl"

  export ACTION="CREATE"
  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ DNSEndpoint template not found: /nonexistent/template.yaml.tpl"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The template file may be missing or the path is incorrect"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify template exists: ls -la /nonexistent/template.yaml.tpl"
}

# =============================================================================
# CREATE: custom template path
# =============================================================================
@test "manage_route: CREATE - uses custom DNS_ENDPOINT_TEMPLATE when set" {
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/custom-template.yaml.tpl"
  echo "custom template" > "$DNS_ENDPOINT_TEMPLATE"

  export ACTION="CREATE"
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Building DNSEndpoint from template: $DNS_ENDPOINT_TEMPLATE"
  assert_contains "$output" "✅ DNSEndpoint manifest created:"
}

# =============================================================================
# DELETE: success
# =============================================================================
@test "manage_route: DELETE - full success flow" {
  export ACTION="DELETE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Deleting DNSEndpoint for external_dns..."
  assert_contains "$output" "📝 Deleting DNSEndpoint: k8s-my-app-my-scope-scope-123-dns in namespace test-ns"
  assert_contains "$output" "✅ DNSEndpoint deletion completed"
}

# =============================================================================
# DELETE: already deleted (idempotent)
# =============================================================================
@test "manage_route: DELETE - warns when DNSEndpoint already deleted" {
  export ACTION="DELETE"

  kubectl() {
    case "$*" in
      *"delete dnsendpoint"*)
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Deleting DNSEndpoint: k8s-my-app-my-scope-scope-123-dns in namespace test-ns"
  assert_contains "$output" "⚠️  DNSEndpoint 'k8s-my-app-my-scope-scope-123-dns' may already be deleted"
  assert_contains "$output" "✅ DNSEndpoint deletion completed"
}
