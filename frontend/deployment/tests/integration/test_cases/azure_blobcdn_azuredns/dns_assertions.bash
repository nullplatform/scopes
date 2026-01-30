#!/bin/bash
# =============================================================================
# Azure DNS Assertion Functions
#
# Provides assertion functions for validating Azure DNS CNAME record
# configuration in integration tests using the Azure Mock API server.
#
# Variables validated (from network/azure_dns/modules/variables.tf):
#   - network_domain          -> DNS zone name
#   - network_subdomain       -> CNAME record name
#
# Usage:
#   source "dns_assertions.bash"
#   assert_azure_dns_configured "subdomain" "domain.com" "sub-id" "rg"
#
# Note: Uses azure_mock() helper from integration_helpers.sh
# =============================================================================

# =============================================================================
# Azure DNS Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | CNAME Record exists              | Non-empty ID                           |
# | Record name                      | expected subdomain                     |
# | CNAME target                     | Non-empty (points to CDN)              |
# | TTL                              | > 0                                    |
# +----------------------------------+----------------------------------------+
assert_azure_dns_configured() {
  local subdomain="$1"
  local zone_name="$2"
  local subscription_id="$3"
  local resource_group="$4"

  # Get DNS CNAME Record
  local record_path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Network/dnszones/${zone_name}/CNAME/${subdomain}"
  local record_json
  record_json=$(azure_mock "$record_path")

  # Record exists
  local record_id
  record_id=$(echo "$record_json" | jq -r '.id // empty')
  assert_not_empty "$record_id" "Azure DNS CNAME Record ID"

  # Record name
  local record_name
  record_name=$(echo "$record_json" | jq -r '.name // empty')
  assert_equal "$record_name" "$subdomain"

  # CNAME target (should point to CDN endpoint)
  local cname_target
  cname_target=$(echo "$record_json" | jq -r '.properties.CNAMERecord.cname // empty')
  assert_not_empty "$cname_target" "Azure DNS CNAME target"

  # The CNAME should point to the Azure CDN endpoint (azureedge.net)
  assert_contains "$cname_target" "azureedge.net"

  # TTL should be positive
  local ttl
  ttl=$(echo "$record_json" | jq -r '.properties.TTL // 0')
  if [[ "$ttl" -le 0 ]]; then
    echo "Expected TTL > 0, got $ttl"
    return 1
  fi

  # FQDN should be set correctly
  local fqdn
  fqdn=$(echo "$record_json" | jq -r '.properties.fqdn // empty')
  assert_contains "$fqdn" "${subdomain}.${zone_name}"
}

# =============================================================================
# Azure DNS Not Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | CNAME Record exists              | null/empty (deleted)                   |
# +----------------------------------+----------------------------------------+
assert_azure_dns_not_configured() {
  local subdomain="$1"
  local zone_name="$2"
  local subscription_id="$3"
  local resource_group="$4"

  # Check CNAME Record is deleted
  local record_path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Network/dnszones/${zone_name}/CNAME/${subdomain}"
  local record_json
  record_json=$(azure_mock "$record_path")

  local record_error
  record_error=$(echo "$record_json" | jq -r '.error.code // empty')
  if [[ "$record_error" != "ResourceNotFound" ]]; then
    local record_id
    record_id=$(echo "$record_json" | jq -r '.id // empty')
    if [[ -n "$record_id" && "$record_id" != "null" ]]; then
      echo "Expected Azure DNS CNAME Record to be deleted"
      echo "Actual: '$record_json'"
      return 1
    fi
  fi

  return 0
}
