#!/bin/bash
# =============================================================================
# Route53 Assertion Functions
#
# Provides assertion functions for validating Route53 record configuration
# in integration tests.
#
# Variables validated (from network/route53/modules/variables.tf):
#   - network_hosted_zone_id  -> Record is in the correct hosted zone
#   - network_domain          -> Part of full domain name
#   - network_subdomain       -> Part of full domain name (subdomain.domain)
#
# Usage:
#   source "route53_assertions.bash"
#   assert_route53_configured "full.domain.com" "A" "hosted-zone-id"
# =============================================================================

# =============================================================================
# Route53 Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | Record exists                    | Non-empty record                       |
# | Record in correct hosted zone    | expected_hosted_zone_id                |
# | Record name                      | domain. (with trailing dot)            |
# | Record type                      | A (exact match)                        |
# | Alias target hosted zone ID      | Z2FDTNDATAQYW2 (CloudFront zone)       |
# | Alias target DNS name            | Contains cloudfront.net                |
# | Evaluate target health           | false                                  |
# +----------------------------------+----------------------------------------+
assert_route53_configured() {
  local full_domain="$1"
  local record_type="${2:-A}"
  local expected_hosted_zone_id="$3"

  # Verify we're querying the correct hosted zone (network_hosted_zone_id)
  local zone_id
  if [[ -n "$expected_hosted_zone_id" ]]; then
    zone_id="$expected_hosted_zone_id"
  else
    # Fallback to first hosted zone if not specified
    zone_id=$(aws_local route53 list-hosted-zones \
      --query "HostedZones[0].Id" \
      --output text 2>/dev/null | sed 's|/hostedzone/||')
  fi

  assert_not_empty "$zone_id" "Route53 hosted zone ID"

  # Verify the hosted zone exists
  local zone_info
  zone_info=$(aws_local route53 get-hosted-zone \
    --id "$zone_id" \
    --output json 2>/dev/null)
  assert_not_empty "$zone_info" "Route53 hosted zone info"

  # Get Route53 record details
  local record_name="${full_domain}."
  local record_json
  record_json=$(aws_local route53 list-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Name=='$record_name' && Type=='$record_type']" \
    --output json 2>/dev/null | jq '.[0]')

  # Record exists
  assert_not_empty "$record_json" "Route53 $record_type record"

  # Record name (with trailing dot) - validates network_domain + network_subdomain
  local actual_name
  actual_name=$(echo "$record_json" | jq -r '.Name')
  assert_equal "$actual_name" "$record_name"

  # Record type
  local actual_type
  actual_type=$(echo "$record_json" | jq -r '.Type')
  assert_equal "$actual_type" "$record_type"

  # Alias target hosted zone ID (CloudFront's global hosted zone)
  local alias_hosted_zone_id
  alias_hosted_zone_id=$(echo "$record_json" | jq -r '.AliasTarget.HostedZoneId // empty')
  assert_equal "$alias_hosted_zone_id" "Z2FDTNDATAQYW2"

  # Alias target DNS name (CloudFront distribution domain)
  # Note: LocalStack may return domain with or without trailing dot
  local alias_target
  alias_target=$(echo "$record_json" | jq -r '.AliasTarget.DNSName // empty')
  assert_not_empty "$alias_target" "Route53 alias target"
  assert_contains "$alias_target" "cloudfront.net"

  # Evaluate target health is false (CloudFront doesn't support health checks)
  local evaluate_target_health
  evaluate_target_health=$(echo "$record_json" | jq -r '.AliasTarget.EvaluateTargetHealth')
  assert_false "$evaluate_target_health" "Route53 evaluate target health"
}

# =============================================================================
# Route53 Not Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | Record exists                    | null/empty (deleted)                   |
# +----------------------------------+----------------------------------------+
assert_route53_not_configured() {
  local full_domain="$1"
  local record_type="${2:-A}"
  local expected_hosted_zone_id="$3"

  local zone_id
  if [[ -n "$expected_hosted_zone_id" ]]; then
    zone_id="$expected_hosted_zone_id"
  else
    zone_id=$(aws_local route53 list-hosted-zones \
      --query "HostedZones[0].Id" \
      --output text 2>/dev/null | sed 's|/hostedzone/||')
  fi

  local record_name="${full_domain}."
  local record_json
  record_json=$(aws_local route53 list-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Name=='$record_name' && Type=='$record_type']" \
    --output json 2>/dev/null | jq '.[0]')

  # jq returns "null" when array is empty, treat as deleted
  if [[ -z "$record_json" || "$record_json" == "null" ]]; then
    return 0
  fi

  echo "Expected Route53 $record_type record to be deleted"
  echo "Actual: '$record_json'"
  return 1
}
