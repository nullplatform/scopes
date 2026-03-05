#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/dns/manage_dns
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SERVICE_PATH="$(mktemp -d)"
  export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/dns/manage_dns"

  # Create mock scripts that succeed by default
  mkdir -p "$SERVICE_PATH/scope/networking/dns/route53"
  mkdir -p "$SERVICE_PATH/scope/networking/dns/external_dns"
  mkdir -p "$SERVICE_PATH/scope/networking/dns/az-records"

  cat > "$SERVICE_PATH/scope/networking/dns/route53/manage_route" << 'MOCK'
echo "route53 manage_route called"
MOCK

  cat > "$SERVICE_PATH/scope/networking/dns/external_dns/manage_route" << 'MOCK'
echo "external_dns manage_route called"
MOCK

  cat > "$SERVICE_PATH/scope/networking/dns/az-records/manage_route" << 'MOCK'
echo "az-records manage_route called"
MOCK

  # Default environment
  export DNS_TYPE="route53"
  export ACTION="CREATE"
  export SCOPE_DOMAIN="test.nullapps.io"
  export SCOPE_VISIBILITY="public"
  export PUBLIC_GATEWAY_NAME="gw-public"
  export PRIVATE_GATEWAY_NAME="gw-private"
  export RESOURCE_GROUP="my-rg"
  export AZURE_SUBSCRIPTION_ID="sub-123"
  export HOSTED_ZONE_NAME="example.com"
  export HOSTED_ZONE_RG="dns-rg"
}

teardown() {
  rm -rf "$SERVICE_PATH"
}

# =============================================================================
# Header messages
# =============================================================================
@test "manage_dns: displays header messages for route53" {
  export DNS_TYPE="route53"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Managing DNS records..."
  assert_contains "$output" "📋 DNS type: route53 | Action: CREATE | Domain: test.nullapps.io"
}

@test "manage_dns: displays header messages for external_dns" {
  export DNS_TYPE="external_dns"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Managing DNS records..."
  assert_contains "$output" "📋 DNS type: external_dns | Action: CREATE | Domain: test.nullapps.io"
}

# =============================================================================
# Route53 dispatching
# =============================================================================
@test "manage_dns: route53 - dispatches to route53/manage_route" {
  export DNS_TYPE="route53"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Using Route53 DNS provider"
  assert_contains "$output" "route53 manage_route called"
  assert_contains "$output" "✅ DNS records managed successfully"
}

@test "manage_dns: route53 - fails with error details when manage_route fails" {
  export DNS_TYPE="route53"

  cat > "$SERVICE_PATH/scope/networking/dns/route53/manage_route" << 'MOCK'
return 1
MOCK

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ]
  assert_contains "$output" "📝 Using Route53 DNS provider"
  assert_contains "$output" "❌ Route53 DNS management failed"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The hosted zone may not exist or the agent lacks Route53 permissions"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check hosted zone exists: aws route53 list-hosted-zones"
}

# =============================================================================
# External DNS dispatching
# =============================================================================
@test "manage_dns: external_dns - dispatches to external_dns/manage_route" {
  export DNS_TYPE="external_dns"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Using External DNS provider"
  assert_contains "$output" "external_dns manage_route called"
  assert_contains "$output" "✅ DNS records managed successfully"
}

@test "manage_dns: external_dns - fails with error details when manage_route fails" {
  export DNS_TYPE="external_dns"

  cat > "$SERVICE_PATH/scope/networking/dns/external_dns/manage_route" << 'MOCK'
return 1
MOCK

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ]
  assert_contains "$output" "📝 Using External DNS provider"
  assert_contains "$output" "❌ External DNS management failed"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The External DNS operator may not be running or lacks permissions"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check operator status: kubectl get pods -l app=external-dns"
}

# =============================================================================
# DELETE with empty domain - skips
# =============================================================================
@test "manage_dns: DELETE with empty SCOPE_DOMAIN - skips action" {
  export ACTION="DELETE"
  export SCOPE_DOMAIN=""

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Managing DNS records..."
  assert_contains "$output" "⚠️  Skipping DNS action — scope has no domain"
}

# =============================================================================
# DELETE with "To be defined" domain - skips
# =============================================================================
@test "manage_dns: DELETE with 'To be defined' SCOPE_DOMAIN - skips action" {
  export ACTION="DELETE"
  export SCOPE_DOMAIN="To be defined"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Managing DNS records..."
  assert_contains "$output" "⚠️  Skipping DNS action — scope has no domain"
}

# =============================================================================
# DELETE with valid domain - does not skip
# =============================================================================
@test "manage_dns: DELETE with valid SCOPE_DOMAIN - proceeds normally" {
  export ACTION="DELETE"
  export SCOPE_DOMAIN="test.nullapps.io"
  export DNS_TYPE="route53"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Using Route53 DNS provider"
  assert_contains "$output" "route53 manage_route called"
  assert_contains "$output" "✅ DNS records managed successfully"
}

# =============================================================================
# CREATE with empty domain - does not skip (only DELETE skips)
# =============================================================================
@test "manage_dns: CREATE with empty SCOPE_DOMAIN - proceeds normally" {
  export ACTION="CREATE"
  export SCOPE_DOMAIN=""
  export DNS_TYPE="route53"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Using Route53 DNS provider"
  assert_contains "$output" "route53 manage_route called"
}

# =============================================================================
# Unsupported DNS type
# =============================================================================
@test "manage_dns: unsupported DNS type - fails with error details" {
  export DNS_TYPE="cloudflare"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Unsupported DNS type: 'cloudflare'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The DNS_TYPE value in values.yaml is not one of: route53, azure, external_dns"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Supported types: route53, azure, external_dns"
}

# =============================================================================
# Azure dispatching
# =============================================================================
@test "manage_dns: azure public - dispatches to az-records/manage_route" {
  export DNS_TYPE="azure"
  export SCOPE_VISIBILITY="public"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 DNS type: azure | Action: CREATE | Domain: test.nullapps.io"
  assert_contains "$output" "📝 Using Azure DNS provider (gateway: gw-public)"
  assert_contains "$output" "az-records manage_route called"
  assert_contains "$output" "✅ DNS records managed successfully"
}

@test "manage_dns: azure private - dispatches to az-records/manage_route" {
  export DNS_TYPE="azure"
  export SCOPE_VISIBILITY="private"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Using Azure DNS provider (gateway: gw-private)"
  assert_contains "$output" "az-records manage_route called"
  assert_contains "$output" "✅ DNS records managed successfully"
}
