#!/usr/bin/env bats
# =============================================================================
# Unit tests for networking/resolve_balancer
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  source "$PROJECT_ROOT/k8s/utils/get_config_value"

  export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/resolve_balancer"
  export REGION="us-east-1"

  # Default: no aws/kubectl commands needed (no additional balancers)
  aws() { return 1; }
  export -f aws
  kubectl() { return 1; }
  export -f kubectl

  # Base CONTEXT — scope creation (no deployment field)
  export CONTEXT='{
    "scope": {
      "id": "test-scope-123",
      "domain": "test.nullapps.io"
    },
    "providers": {
      "scope-configurations": {},
      "cloud-providers": {
        "networking": {
          "hosted_public_zone_id": "Z1234567890",
          "hosted_zone_id": "Z0987654321"
        }
      },
      "container-orchestration": {
        "cluster": {
          "namespace": "test-ns"
        },
        "balancer": {
          "public_name": "co-balancer-public",
          "private_name": "co-balancer-private"
        }
      }
    }
  }'
}

teardown() {
  unset -f aws
  unset -f kubectl
  unset -f log
  unset -f get_config_value
  unset -f get_alb_rule_count
  unset -f get_alb_from_ingress
  unset -f get_alb_from_route53
  unset ALB_NAME
  unset ADDITIONAL_BALANCERS
}

# Helper: add deployment field to CONTEXT (makes it a deployment context)
add_deployment_context() {
  export CONTEXT=$(echo "$CONTEXT" | jq '. + {deployment: {id: "deploy-456"}}')
}

# =============================================================================
# Default ALB name (no provider config)
# =============================================================================
@test "resolve_balancer: uses default ALB name when no provider config (public)" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT='{ "providers": {} }'

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "k8s-nullplatform-internet-facing"
}

@test "resolve_balancer: uses default ALB name when no provider config (private)" {
  export INGRESS_VISIBILITY="internal"
  export CONTEXT='{ "providers": {} }'

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "k8s-nullplatform-internal"
}

# =============================================================================
# Provider overrides - container-orchestration
# =============================================================================
@test "resolve_balancer: resolves public ALB from container-orchestration provider" {
  export INGRESS_VISIBILITY="internet-facing"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

@test "resolve_balancer: resolves private ALB from container-orchestration provider" {
  export INGRESS_VISIBILITY="internal"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-private"
}

# =============================================================================
# Provider overrides - scope-configurations takes priority
# =============================================================================
@test "resolve_balancer: scope-configurations overrides container-orchestration (public)" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].networking.balancer_public_name = "scope-alb-public"')

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "scope-alb-public"
}

@test "resolve_balancer: scope-configurations overrides container-orchestration (private)" {
  export INGRESS_VISIBILITY="internal"
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].networking.balancer_private_name = "scope-alb-private"')

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "scope-alb-private"
}

# =============================================================================
# Scope creation: additional balancers — least-loaded selection
# =============================================================================
@test "resolve_balancer: selects ALB with fewest rules from candidates (public)" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1", "alb-extra-2"]
  ')

  get_alb_rule_count() {
    case "$1" in
      co-balancer-public) echo "45" ;;
      alb-extra-1)        echo "12" ;;
      alb-extra-2)        echo "30" ;;
    esac
  }
  export -f get_alb_rule_count

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-extra-1"
}

@test "resolve_balancer: selects ALB with fewest rules from candidates (private)" {
  export INGRESS_VISIBILITY="internal"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_private_balancers = ["alb-priv-extra-1", "alb-priv-extra-2"]
  ')

  get_alb_rule_count() {
    case "$1" in
      co-balancer-private) echo "50" ;;
      alb-priv-extra-1)    echo "20" ;;
      alb-priv-extra-2)    echo "5"  ;;
    esac
  }
  export -f get_alb_rule_count

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-priv-extra-2"
}

@test "resolve_balancer: keeps default ALB when it has fewest rules" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  get_alb_rule_count() {
    case "$1" in
      co-balancer-public) echo "5"  ;;
      alb-extra-1)        echo "30" ;;
    esac
  }
  export -f get_alb_rule_count

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

@test "resolve_balancer: logs selected ALB when different from default" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  get_alb_rule_count() {
    case "$1" in
      co-balancer-public) echo "45" ;;
      alb-extra-1)        echo "12" ;;
    esac
  }
  export -f get_alb_rule_count

  run bash -c 'source "$SCRIPT"'

  assert_contains "$output" "📝 Selected ALB 'alb-extra-1' (12 rules) over default 'co-balancer-public'"
}

@test "resolve_balancer: logs candidate balancers list" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1", "alb-extra-2"]
  ')

  get_alb_rule_count() { echo "10"; }
  export -f get_alb_rule_count

  run bash -c 'export LOG_LEVEL=debug; source "$SCRIPT"'

  assert_contains "$output" "🔍 Additional balancers configured, resolving least-loaded ALB..."
  assert_contains "$output" "📋 Candidate balancers: co-balancer-public, alb-extra-1, alb-extra-2"
}

# =============================================================================
# AWS API failure handling
# =============================================================================
@test "resolve_balancer: skips candidate when AWS query fails" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1", "alb-extra-2"]
  ')

  get_alb_rule_count() {
    case "$1" in
      co-balancer-public) echo "45" ;;
      alb-extra-1)        return 1 ;;
      alb-extra-2)        echo "20" ;;
    esac
  }
  export -f get_alb_rule_count

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-extra-2"
}

@test "resolve_balancer: warns when a candidate fails" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-broken"]
  ')

  get_alb_rule_count() {
    case "$1" in
      co-balancer-public) echo "10" ;;
      alb-broken)         return 1 ;;
    esac
  }
  export -f get_alb_rule_count

  run bash -c 'source "$SCRIPT"'

  assert_contains "$output" "⚠️  Could not query rules for ALB 'alb-broken', skipping"
}

@test "resolve_balancer: keeps default when all candidates fail" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-broken-1", "alb-broken-2"]
  ')

  get_alb_rule_count() { return 1; }
  export -f get_alb_rule_count

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

# =============================================================================
# No additional balancers — no AWS calls
# =============================================================================
@test "resolve_balancer: does not call AWS when no additional balancers configured" {
  export INGRESS_VISIBILITY="internet-facing"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

@test "resolve_balancer: handles empty additional balancers array gracefully" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = []
  ')

  get_alb_rule_count() { echo "10"; }
  export -f get_alb_rule_count

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

# =============================================================================
# Tie-breaking: first candidate with fewest rules wins
# =============================================================================
@test "resolve_balancer: picks first candidate on tie" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1", "alb-extra-2"]
  ')

  get_alb_rule_count() {
    case "$1" in
      co-balancer-public) echo "10" ;;
      alb-extra-1)        echo "10" ;;
      alb-extra-2)        echo "10" ;;
    esac
  }
  export -f get_alb_rule_count

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

# =============================================================================
# Deployment time: ALB lookup from existing infrastructure
# =============================================================================
@test "resolve_balancer: deployment uses ALB from existing ingress" {
  export INGRESS_VISIBILITY="internet-facing"
  add_deployment_context
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  get_alb_from_ingress() { echo "alb-extra-1"; }
  export -f get_alb_from_ingress

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-extra-1"
}

@test "resolve_balancer: deployment falls back to Route53 when no ingress exists" {
  export INGRESS_VISIBILITY="internet-facing"
  add_deployment_context
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  get_alb_from_ingress() { return 1; }
  export -f get_alb_from_ingress
  get_alb_from_route53() { echo "alb-extra-1"; }
  export -f get_alb_from_route53

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-extra-1"
}

@test "resolve_balancer: deployment falls back to calculation when no infrastructure found" {
  export INGRESS_VISIBILITY="internet-facing"
  add_deployment_context
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  get_alb_from_ingress() { return 1; }
  export -f get_alb_from_ingress
  get_alb_from_route53() { return 1; }
  export -f get_alb_from_route53
  get_alb_rule_count() {
    case "$1" in
      co-balancer-public) echo "45" ;;
      alb-extra-1)        echo "10" ;;
    esac
  }
  export -f get_alb_rule_count

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-extra-1"
}

@test "resolve_balancer: deployment logs when using ALB from ingress" {
  export INGRESS_VISIBILITY="internet-facing"
  add_deployment_context
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  get_alb_from_ingress() { echo "alb-from-ingress"; }
  export -f get_alb_from_ingress

  run bash -c 'export LOG_LEVEL=debug; source "$SCRIPT"'

  assert_contains "$output" "📋 Found ALB 'alb-from-ingress' from existing ingress for scope test-scope-123"
  assert_contains "$output" "📝 Using existing ALB 'alb-from-ingress' (consistent with DNS)"
}

@test "resolve_balancer: deployment logs when using ALB from Route53" {
  export INGRESS_VISIBILITY="internet-facing"
  add_deployment_context
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  get_alb_from_ingress() { return 1; }
  export -f get_alb_from_ingress
  get_alb_from_route53() { echo "alb-from-dns"; }
  export -f get_alb_from_route53

  run bash -c 'export LOG_LEVEL=debug; source "$SCRIPT"'

  assert_contains "$output" "📋 Found ALB 'alb-from-dns' from Route53 record for test.nullapps.io"
  assert_contains "$output" "📝 Using existing ALB 'alb-from-dns' (consistent with DNS)"
}

@test "resolve_balancer: deployment warns when falling back to calculation" {
  export INGRESS_VISIBILITY="internet-facing"
  add_deployment_context
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  get_alb_from_ingress() { return 1; }
  export -f get_alb_from_ingress
  get_alb_from_route53() { return 1; }
  export -f get_alb_from_route53
  get_alb_rule_count() { echo "10"; }
  export -f get_alb_rule_count

  run bash -c 'source "$SCRIPT"'

  assert_contains "$output" "⚠️  Could not determine existing ALB from infrastructure, recalculating"
}

@test "resolve_balancer: scope creation always calculates even when ingress exists" {
  export INGRESS_VISIBILITY="internet-facing"
  # No deployment in context — this is scope creation
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')

  # Even though ingress mock returns a value, scope creation should calculate
  get_alb_from_ingress() { echo "old-alb-from-ingress"; }
  export -f get_alb_from_ingress
  get_alb_rule_count() {
    case "$1" in
      co-balancer-public) echo "45" ;;
      alb-extra-1)        echo "10" ;;
    esac
  }
  export -f get_alb_rule_count

  source "$SCRIPT"

  # Should use the calculation result, not the ingress value
  assert_equal "$ALB_NAME" "alb-extra-1"
}

@test "resolve_balancer: deployment without additional balancers uses base ALB" {
  export INGRESS_VISIBILITY="internet-facing"
  add_deployment_context

  source "$SCRIPT"

  # No additional balancers = no lookup needed, uses base ALB
  assert_equal "$ALB_NAME" "co-balancer-public"
}
