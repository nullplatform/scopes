#!/bin/bash
# =============================================================================
# Azure CDN Assertion Functions
#
# Provides assertion functions for validating Azure CDN endpoint
# configuration in integration tests using the Azure Mock API server.
#
# Variables validated (from distribution/azure_blob_cdn/modules/variables.tf):
#   - distribution_storage_account  -> Origin host
#   - distribution_app_name         -> CDN profile/endpoint name
#
# Usage:
#   source "cdn_assertions.bash"
#   assert_azure_cdn_configured "app-name" "storage-account" "sub-id" "rg"
#
# Note: Uses azure_mock() helper from integration_helpers.sh
# =============================================================================

# =============================================================================
# Azure CDN Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | CDN Profile exists               | Non-empty ID                           |
# | CDN Profile provisioning state   | Succeeded                              |
# | CDN Endpoint exists              | Non-empty ID                           |
# | CDN Endpoint provisioning state  | Succeeded                              |
# | CDN Endpoint hostname            | Contains azureedge.net                 |
# | Origin host contains             | storage account name                   |
# +----------------------------------+----------------------------------------+
assert_azure_cdn_configured() {
  local app_name="$1"
  local storage_account="$2"
  local subscription_id="$3"
  local resource_group="$4"

  # Derive CDN profile and endpoint names from app_name
  # The terraform module uses: "${var.distribution_app_name}-cdn" for profile
  # and "${var.distribution_app_name}" for endpoint
  local profile_name="${app_name}-cdn"
  local endpoint_name="${app_name}"

  # Get CDN Profile
  local profile_path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Cdn/profiles/${profile_name}"
  local profile_json
  profile_json=$(azure_mock "$profile_path")

  # Profile exists
  local profile_id
  profile_id=$(echo "$profile_json" | jq -r '.id // empty')
  assert_not_empty "$profile_id" "Azure CDN Profile ID"

  # Profile provisioning state
  local profile_state
  profile_state=$(echo "$profile_json" | jq -r '.properties.provisioningState // empty')
  assert_equal "$profile_state" "Succeeded"

  # Get CDN Endpoint
  local endpoint_path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Cdn/profiles/${profile_name}/endpoints/${endpoint_name}"
  local endpoint_json
  endpoint_json=$(azure_mock "$endpoint_path")

  # Endpoint exists
  local endpoint_id
  endpoint_id=$(echo "$endpoint_json" | jq -r '.id // empty')
  assert_not_empty "$endpoint_id" "Azure CDN Endpoint ID"

  # Endpoint provisioning state
  local endpoint_state
  endpoint_state=$(echo "$endpoint_json" | jq -r '.properties.provisioningState // empty')
  assert_equal "$endpoint_state" "Succeeded"

  # Endpoint hostname contains azureedge.net
  local hostname
  hostname=$(echo "$endpoint_json" | jq -r '.properties.hostName // empty')
  assert_not_empty "$hostname" "Azure CDN Endpoint hostname"
  assert_contains "$hostname" "azureedge.net"

  # Origin host contains storage account name
  local origin_host
  origin_host=$(echo "$endpoint_json" | jq -r '.properties.origins[0].properties.hostName // empty')
  assert_not_empty "$origin_host" "Azure CDN Origin host"
  assert_contains "$origin_host" "$storage_account"
}

# =============================================================================
# Azure CDN Not Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | CDN Profile exists               | null/empty (deleted)                   |
# | CDN Endpoint exists              | null/empty (deleted)                   |
# +----------------------------------+----------------------------------------+
assert_azure_cdn_not_configured() {
  local app_name="$1"
  local subscription_id="$2"
  local resource_group="$3"

  local profile_name="${app_name}-cdn"
  local endpoint_name="${app_name}"

  # Check CDN Profile is deleted
  local profile_path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Cdn/profiles/${profile_name}"
  local profile_json
  profile_json=$(azure_mock "$profile_path")

  local profile_error
  profile_error=$(echo "$profile_json" | jq -r '.error.code // empty')
  if [[ "$profile_error" != "ResourceNotFound" ]]; then
    local profile_id
    profile_id=$(echo "$profile_json" | jq -r '.id // empty')
    if [[ -n "$profile_id" && "$profile_id" != "null" ]]; then
      echo "Expected Azure CDN Profile to be deleted"
      echo "Actual: '$profile_json'"
      return 1
    fi
  fi

  # Check CDN Endpoint is deleted
  local endpoint_path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Cdn/profiles/${profile_name}/endpoints/${endpoint_name}"
  local endpoint_json
  endpoint_json=$(azure_mock "$endpoint_path")

  local endpoint_error
  endpoint_error=$(echo "$endpoint_json" | jq -r '.error.code // empty')
  if [[ "$endpoint_error" != "ResourceNotFound" ]]; then
    local endpoint_id
    endpoint_id=$(echo "$endpoint_json" | jq -r '.id // empty')
    if [[ -n "$endpoint_id" && "$endpoint_id" != "null" ]]; then
      echo "Expected Azure CDN Endpoint to be deleted"
      echo "Actual: '$endpoint_json'"
      return 1
    fi
  fi

  return 0
}
