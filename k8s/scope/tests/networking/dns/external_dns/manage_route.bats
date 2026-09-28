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
  export CONTEXT='{"scope":{"slug":"my-scope"},"application":{"slug":"my-app"},"names":{"scope_dns":"k8s-my-app-my-scope-scope-123-dns"}}'
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
# CREATE: GATEWAY_EXTERNAL_IP override - an IP yields an A record
# =============================================================================
@test "manage_route: CREATE - uses GATEWAY_EXTERNAL_IP when set, skips kubectl lookups" {
  export ACTION="CREATE"
  export GATEWAY_EXTERNAL_IP="192.0.2.200"
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  # Any kubectl call aborts the script: the lookups run as VAR=$(kubectl ...)
  # under set -e, so a non-zero return fails the status assertion below. The
  # message never surfaces -- the script's own 2>/dev/null swallows it.
  kubectl() { echo "kubectl should not be called: $*" >&2; return 1; }
  export -f kubectl

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📡 Using GATEWAY_EXTERNAL_IP override: 192.0.2.200 (recordType: A)"
  assert_contains "$output" "✅ Gateway address: 192.0.2.200 (recordType: A)"
  assert_contains "$output" "✅ DNSEndpoint manifest created:"
}

# =============================================================================
# CREATE: GATEWAY_EXTERNAL_IP override - a hostname yields a CNAME
# =============================================================================
@test "manage_route: CREATE - GATEWAY_EXTERNAL_IP with a hostname yields a CNAME" {
  export ACTION="CREATE"
  export GATEWAY_EXTERNAL_IP="gateway.example.com"
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Gateway address: gateway.example.com (recordType: CNAME)"
}

# =============================================================================
# CREATE: GATEWAY_EXTERNAL_IP override - malformed values fail loudly
# =============================================================================
@test "manage_route: CREATE - GATEWAY_EXTERNAL_IP with a scheme or port fails with guidance" {
  export ACTION="CREATE"
  export GATEWAY_EXTERNAL_IP="http://192.0.2.200:8080"
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ GATEWAY_EXTERNAL_IP is neither an IPv4 address nor a hostname"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# CREATE: GATEWAY_EXTERNAL_IP override - blank values mean "not set"
# =============================================================================
@test "manage_route: CREATE - whitespace-only GATEWAY_EXTERNAL_IP falls back to auto-detection" {
  export ACTION="CREATE"
  export GATEWAY_EXTERNAL_IP="   "
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Gateway address: 10.0.0.1 (recordType: A)"
}

@test "manage_route: CREATE - empty-string GATEWAY_EXTERNAL_IP falls back to auto-detection" {
  export ACTION="CREATE"
  export GATEWAY_EXTERNAL_IP=""
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Gateway address: 10.0.0.1 (recordType: A)"
}

# =============================================================================
# CREATE: no override leaves the auto-detection chain untouched
# =============================================================================
@test "manage_route: CREATE - falls back to auto-detection when GATEWAY_EXTERNAL_IP is unset" {
  export ACTION="CREATE"
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📡 ALB Ingress not found, resolving gateway address directly..."
  assert_contains "$output" "✅ Gateway address: 10.0.0.1 (recordType: A)"
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
# CREATE: a genuine NotFound falls through instead of killing the script
# =============================================================================
@test "manage_route: CREATE - a NotFound on the ALB Ingress falls through to the Gateway" {
  export ACTION="CREATE"
  export DNS_ENDPOINT_TEMPLATE="$OUTPUT_DIR/dns-endpoint.yaml.tpl"
  echo "template content" > "$DNS_ENDPOINT_TEMPLATE"

  # Real kubectl exits 1 when the named resource does not exist, which is what
  # an on-premise cluster does for the AWS-only ALB Ingress. The shared mock in
  # setup() always exits 0, so this case was never covered.
  kubectl() {
    case "$*" in
      *"get ingress"*) return 1 ;;
      *"get gateway"*) echo "10.0.0.1" ;;
      *) echo "" ;;
    esac
  }
  export -f kubectl

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Gateway address: 10.0.0.1 (recordType: A)"
}

@test "manage_route: CREATE - every lookup failing still exits 0 with guidance" {
  export ACTION="CREATE"

  kubectl() { return 1; }
  export -f kubectl

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  Could not determine gateway IP address yet"
  assert_contains "$output" "If it persists: kubectl get gateway,service -n gateways"
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

@test "manage_route: DELETE - targets the resolved DNS endpoint name from context, not a constructed one" {
  export ACTION="DELETE"
  export CONTEXT='{"scope":{"slug":"my-scope"},"application":{"slug":"my-app"},"names":{"scope_dns":"checkout-api-production-123456-dns"}}'

  kubectl() {
    echo "kubectl $*" >> "$OUTPUT_DIR/kubectl.log"
    case "$*" in
      *"delete dnsendpoint checkout-api-production-123456-dns -n test-ns"*)
        return 0
        ;;
      *"delete dnsendpoint"*)
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Deleting DNSEndpoint: checkout-api-production-123456-dns in namespace test-ns"
  assert_contains "$output" "✅ DNSEndpoint deletion completed"
  assert_contains "$(cat "$OUTPUT_DIR/kubectl.log")" "delete dnsendpoint checkout-api-production-123456-dns -n test-ns"
}
