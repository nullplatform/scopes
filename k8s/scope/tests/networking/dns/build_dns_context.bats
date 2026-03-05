#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/dns/build_dns_context
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export SCRIPT="$SERVICE_PATH/scope/networking/dns/build_dns_context"

  # Azure defaults
  export HOSTED_ZONE_NAME="example.com"
  export HOSTED_ZONE_RG="dns-rg"
  export AZURE_SUBSCRIPTION_ID="sub-123"
  export RESOURCE_GROUP="my-rg"
  export PUBLIC_GATEWAY_NAME="gw-public"
  export PRIVATE_GATEWAY_NAME="gw-private"

  # Route53 defaults
  export CONTEXT='{"providers":{"cloud-providers":{"networking":{"hosted_public_zone_id":"Z123","hosted_zone_id":"Z456"}}}}'
}

teardown() {
  rm -rf "$SERVICE_PATH/tmp" "$SERVICE_PATH/output"
}

# =============================================================================
# Azure DNS type
# =============================================================================
@test "build_dns_context: azure - displays full configuration" {
  export DNS_TYPE="azure"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Building DNS context..."
  assert_contains "$output" "📋 DNS type: azure"
  assert_contains "$output" "📋 Azure DNS configuration:"
  assert_contains "$output" "Gateway type: istio"
  assert_contains "$output" "Hosted zone: example.com (RG: dns-rg)"
  assert_contains "$output" "Subscription: sub-123"
  assert_contains "$output" "Resource group: my-rg"
  assert_contains "$output" "Public gateway: gw-public"
  assert_contains "$output" "Private gateway: gw-private"
  assert_contains "$output" "✅ DNS context ready"
}

@test "build_dns_context: azure - defaults GATEWAY_TYPE to istio when not set" {
  export DNS_TYPE="azure"
  unset GATEWAY_TYPE

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "Gateway type: istio"
}

@test "build_dns_context: azure - uses custom GATEWAY_TYPE when set" {
  export DNS_TYPE="azure"
  export GATEWAY_TYPE="nginx"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "Gateway type: nginx"
}

# =============================================================================
# External DNS type
# =============================================================================
@test "build_dns_context: external_dns - displays context" {
  export DNS_TYPE="external_dns"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Building DNS context..."
  assert_contains "$output" "📋 DNS type: external_dns"
  assert_contains "$output" "📋 DNS records will be managed automatically by External DNS operator"
  assert_contains "$output" "✅ DNS context ready"
}

# =============================================================================
# Route53 DNS type
# =============================================================================
@test "build_dns_context: route53 - sources get_hosted_zones" {
  export DNS_TYPE="route53"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Building DNS context..."
  assert_contains "$output" "📋 DNS type: route53"
  assert_contains "$output" "Getting hosted zones"
  assert_contains "$output" "Public Hosted Zone ID: Z123"
  assert_contains "$output" "Private Hosted Zone ID: Z456"
  assert_contains "$output" "✅ DNS context ready"
}

# =============================================================================
# Unsupported DNS type
# =============================================================================
@test "build_dns_context: unsupported type - fails with error details" {
  export DNS_TYPE="cloudflare"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Unsupported DNS type: 'cloudflare'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The DNS_TYPE value in values.yaml is not one of: route53, azure, external_dns"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Supported types: route53, azure, external_dns"
}

@test "build_dns_context: empty DNS_TYPE - fails with error details" {
  export DNS_TYPE=""

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Unsupported DNS type: ''"
}
