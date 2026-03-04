#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/dns/az-records/manage_route
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export SCRIPT="$SERVICE_PATH/scope/networking/dns/az-records/manage_route"

  # Default environment
  export GATEWAY_TYPE="istio"
  export SCOPE_DOMAIN="myapp.example.com"
  export HOSTED_ZONE_NAME="example.com"
  export AZURE_TENANT_ID="tenant-123"
  export AZURE_CLIENT_ID="client-123"
  export AZURE_CLIENT_SECRET="secret-123"

  # Mock kubectl - default: return gateway IP
  kubectl() {
    case "$*" in
      *"get gateway"*)
        echo "10.0.0.1"
        ;;
      *"get svc router-default"*)
        echo "10.0.0.2"
        ;;
    esac
  }
  export -f kubectl

  # Mock curl - default: token succeeds, DNS API succeeds
  curl() {
    if [[ "$*" == *"login.microsoftonline.com"* ]]; then
      echo '{"access_token":"mock-token-123","token_type":"Bearer"}'
      echo "__HTTP_CODE__:200"
    elif [[ "$*" == *"management.azure.com"* ]] && [[ "$*" == *"PUT"* ]]; then
      echo '{"id":"/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/dnsZones/example.com/A/myapp"}'
      echo "__HTTP_CODE__:200"
    elif [[ "$*" == *"management.azure.com"* ]] && [[ "$*" == *"DELETE"* ]]; then
      echo ""
    fi
  }
  export -f curl
}

# =============================================================================
# CREATE: success with istio gateway
# =============================================================================
@test "manage_route: CREATE with istio gateway - full success flow" {
  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Managing Azure DNS record..."
  assert_contains "$output" "📋 Action: CREATE | Gateway: gw-public | Zone: example.com"
  assert_contains "$output" "📡 Getting IP from gateway 'gw-public'..."
  assert_contains "$output" "✅ Gateway IP: 10.0.0.1"
  assert_contains "$output" "📋 Subdomain: myapp | Zone: example.com | IP: 10.0.0.1"
  assert_contains "$output" "📝 Creating Azure DNS record..."
  assert_contains "$output" "✅ DNS record created: myapp.example.com -> 10.0.0.1"
}

# =============================================================================
# CREATE: success with ARO cluster
# =============================================================================
@test "manage_route: CREATE with aro_cluster gateway - uses router service" {
  export GATEWAY_TYPE="aro_cluster"

  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 0 ]
  assert_contains "$output" "📡 Getting IP from ARO router service..."
  assert_contains "$output" "✅ Gateway IP: 10.0.0.2"
}

# =============================================================================
# CREATE: ARO fallback to istio
# =============================================================================
@test "manage_route: CREATE with aro_cluster - falls back to istio when router has no IP" {
  export GATEWAY_TYPE="aro_cluster"

  kubectl() {
    case "$*" in
      *"get svc router-default"*)
        echo ""
        ;;
      *"get gateway"*)
        echo "10.0.0.1"
        ;;
    esac
  }
  export -f kubectl

  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 0 ]
  assert_contains "$output" "📡 Getting IP from ARO router service..."
  assert_contains "$output" "⚠️  ARO router IP not found, falling back to istio gateway..."
  assert_contains "$output" "✅ Gateway IP: 10.0.0.1"
}

# =============================================================================
# DELETE: success
# =============================================================================
@test "manage_route: DELETE - full success flow" {
  run bash "$SCRIPT" \
    --action=DELETE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Managing Azure DNS record..."
  assert_contains "$output" "📋 Action: DELETE | Gateway: gw-public | Zone: example.com"
  assert_contains "$output" "📝 Deleting Azure DNS record..."
  assert_contains "$output" "✅ DNS record deleted: myapp.example.com"
}

# =============================================================================
# Error: gateway IP not found
# =============================================================================
@test "manage_route: fails with error details when gateway IP not found" {
  kubectl() { echo ""; }
  export -f kubectl

  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not get IP address for gateway 'gw-public'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The gateway may not be ready or the name is incorrect"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check gateway status: kubectl get gateway gw-public -n gateways"
}

# =============================================================================
# Error: Azure token failure (curl fails)
# =============================================================================
@test "manage_route: fails with error details when Azure token request fails" {
  curl() {
    if [[ "$*" == *"login.microsoftonline.com"* ]]; then
      return 1
    fi
  }
  export -f curl

  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to get Azure access token"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The Azure credentials may be invalid or expired"
}

# =============================================================================
# Error: Azure token failure (HTTP error)
# =============================================================================
@test "manage_route: fails with error details when Azure token returns HTTP error" {
  curl() {
    if [[ "$*" == *"login.microsoftonline.com"* ]]; then
      echo '{"error":"invalid_client"}'
      echo "__HTTP_CODE__:401"
    fi
  }
  export -f curl

  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to get Azure access token (HTTP 401)"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The Azure credentials may be invalid or expired"
}

# =============================================================================
# Error: Azure DNS API returns error
# =============================================================================
@test "manage_route: fails with error details when Azure DNS API returns error" {
  curl() {
    if [[ "$*" == *"login.microsoftonline.com"* ]]; then
      echo '{"access_token":"mock-token-123","token_type":"Bearer"}'
      echo "__HTTP_CODE__:200"
    elif [[ "$*" == *"management.azure.com"* ]] && [[ "$*" == *"PUT"* ]]; then
      echo '{"error":{"code":"ResourceNotFound","message":"DNS zone not found"}}'
      echo "__HTTP_CODE__:200"
    fi
  }
  export -f curl

  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Azure API returned an error creating DNS record"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The DNS zone or resource group may not exist, or permissions are insufficient"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify DNS zone 'example.com' exists in resource group 'dns-rg'"
}

# =============================================================================
# Error: Azure DNS API returns non-2xx HTTP
# =============================================================================
@test "manage_route: fails with error details when Azure DNS API returns HTTP error" {
  curl() {
    if [[ "$*" == *"login.microsoftonline.com"* ]]; then
      echo '{"access_token":"mock-token-123","token_type":"Bearer"}'
      echo "__HTTP_CODE__:200"
    elif [[ "$*" == *"management.azure.com"* ]] && [[ "$*" == *"PUT"* ]]; then
      echo '{"message":"Forbidden"}'
      echo "__HTTP_CODE__:403"
    fi
  }
  export -f curl

  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Azure API returned HTTP 403"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The DNS zone or resource group may not exist, or permissions are insufficient"
}

# =============================================================================
# Custom SCOPE_SUBDOMAIN
# =============================================================================
@test "manage_route: uses custom SCOPE_SUBDOMAIN when set" {
  export SCOPE_SUBDOMAIN="custom-sub"

  run bash "$SCRIPT" \
    --action=CREATE \
    --resource-group=my-rg \
    --subscription-id=sub-123 \
    --gateway-name=gw-public \
    --hosted-zone-name=example.com \
    --hosted-zone-rg=dns-rg

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Subdomain: custom-sub | Zone: example.com | IP: 10.0.0.1"
  assert_contains "$output" "✅ DNS record created: custom-sub.example.com -> 10.0.0.1"
}
