#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/dns/route53/manage_route
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export SCRIPT="$SERVICE_PATH/scope/networking/dns/route53/manage_route"

  # Default environment
  export ALB_NAME="my-alb"
  export REGION="us-east-1"
  export SCOPE_DOMAIN="test.nullapps.io"
  export HOSTED_PRIVATE_ZONE_ID="Z_PRIVATE_123"
  export HOSTED_PUBLIC_ZONE_ID="Z_PUBLIC_456"

  # Mock aws CLI - default: describe-load-balancers succeeds, change-resource-record-sets succeeds
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "my-alb-dns.us-east-1.elb.amazonaws.com Z_ELB_789"
        ;;
      *"change-resource-record-sets"*)
        echo '{"ChangeInfo":{"Status":"PENDING"}}'
        ;;
    esac
  }
  export -f aws
}

# =============================================================================
# Success: both zones
# =============================================================================
@test "manage_route: creates records in both zones when public != private" {
  run bash "$SCRIPT" --action=CREATE

  [ "$status" -eq 0 ]
  assert_contains "$output" "📡 Looking for load balancer: my-alb in region us-east-1..."
  assert_contains "$output" "✅ Found load balancer DNS: my-alb-dns.us-east-1.elb.amazonaws.com"
  assert_contains "$output" "📋 Will create records in both public and private zones"
  assert_contains "$output" "📝 CREATING Route53 record in hosted zone: Z_PRIVATE_123"
  assert_contains "$output" "📋 Domain: test.nullapps.io -> my-alb-dns.us-east-1.elb.amazonaws.com"
  assert_contains "$output" "✅ Successfully CREATED public Route53 record"
  assert_contains "$output" "📝 CREATING Route53 record in hosted zone: Z_PUBLIC_456"
  assert_contains "$output" "✨ Route53 DNS configuration completed"
}

# =============================================================================
# Success: only private zone
# =============================================================================
@test "manage_route: creates record in private zone only when public is null" {
  export HOSTED_PUBLIC_ZONE_ID="null"

  run bash "$SCRIPT" --action=CREATE

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 CREATING Route53 record in hosted zone: Z_PRIVATE_123"
  assert_contains "$output" "✅ Successfully CREATED private Route53 record"

  assert_contains "$output" "✨ Route53 DNS configuration completed"
}

# =============================================================================
# Success: same zone ID for public and private (no duplicate)
# =============================================================================
@test "manage_route: creates record once when public == private zone" {
  export HOSTED_PUBLIC_ZONE_ID="Z_PRIVATE_123"

  run bash "$SCRIPT" --action=UPSERT

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 UPSERTING Route53 record in hosted zone: Z_PRIVATE_123"
  assert_contains "$output" "✨ Route53 DNS configuration completed"
}

# =============================================================================
# Error: load balancer not found
# =============================================================================
@test "manage_route: fails with error details when ALB not found" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "An error occurred (LoadBalancerNotFound)" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT" --action=CREATE

  [ "$status" -eq 1 ]
  assert_contains "$output" "📡 Looking for load balancer: my-alb in region us-east-1..."
  assert_contains "$output" "❌ Failed to find load balancer 'my-alb' in region 'us-east-1'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The load balancer may not exist or you lack permissions to describe it"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify the ALB exists: aws elbv2 describe-load-balancers --names my-alb"
}

# =============================================================================
# Error: load balancer has no DNS name
# =============================================================================
@test "manage_route: fails with error details when ALB has no DNS name" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "None None"
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT" --action=CREATE

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Load balancer 'my-alb' exists but has no DNS name"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The load balancer may still be provisioning"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check ALB status: aws elbv2 describe-load-balancers --names my-alb"
}

# =============================================================================
# Error: Route53 change fails
# =============================================================================
@test "manage_route: fails with error details when Route53 change fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "my-alb-dns.us-east-1.elb.amazonaws.com Z_ELB_789"
        ;;
      *"change-resource-record-sets"*)
        echo "An error occurred (AccessDenied)" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT" --action=CREATE

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to CREATE Route53 record"
  assert_contains "$output" "📋 Zone ID: Z_PRIVATE_123"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The agent may lack Route53 permissions"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check IAM permissions for route53:ChangeResourceRecordSets"
}

# =============================================================================
# DELETE: skips when record not found (idempotent)
# =============================================================================
@test "manage_route: DELETE skips when record not found in zone" {
  export HOSTED_PUBLIC_ZONE_ID="null"

  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "my-alb-dns.us-east-1.elb.amazonaws.com Z_ELB_789"
        ;;
      *"change-resource-record-sets"*)
        ROUTE53_OUTPUT="InvalidChangeBatch: it was submitted as part of a batch but it was not found"
        echo "$ROUTE53_OUTPUT" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT" --action=DELETE

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Route53 record for test.nullapps.io does not exist in zone Z_PRIVATE_123, skipping deletion"
  assert_contains "$output" "✨ Route53 DNS configuration completed"
}

# =============================================================================
# DELETE: succeeds normally
# =============================================================================
@test "manage_route: DELETE succeeds when record exists" {
  export HOSTED_PUBLIC_ZONE_ID="null"

  run bash "$SCRIPT" --action=DELETE

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 DELETING Route53 record in hosted zone: Z_PRIVATE_123"
  assert_contains "$output" "✅ Successfully DELETED private Route53 record"
  assert_contains "$output" "✨ Route53 DNS configuration completed"
}
