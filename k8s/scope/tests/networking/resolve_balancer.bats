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

  # Default: aws returns failure (no Route53 record, no ALBs)
  aws() { return 1; }
  export -f aws

  # Temp file for tracking ALB rule counts in mocks
  export MOCK_RULES_FILE="$(mktemp)"

  # Base CONTEXT
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
  unset -f log
  unset -f get_config_value
  rm -f "$MOCK_RULES_FILE"
  unset ALB_NAME
  unset ADDITIONAL_BALANCERS
}

# =============================================================================
# Mock helpers
# =============================================================================

# Sets up aws mock that returns a Route53 record pointing to a specific ALB.
mock_route53_alb() {
  local alb_name="$1"
  local alb_dns="${alb_name}-123.us-east-1.elb.amazonaws.com"

  eval "aws() {
    case \"\$*\" in
      *list-resource-record-sets*)
        echo '${alb_dns}.'
        return 0
        ;;
      *describe-load-balancers*)
        echo '${alb_name}'
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }
  export -f aws"
}

# Sets up aws mock with no Route53 record but with rule counts for ALBs.
# Write rule counts to MOCK_RULES_FILE as "alb_name count" lines.
# The mock returns the ALB ARN with the name embedded so describe-rules
# can look up the correct rule count.
mock_alb_rules() {
  > "$MOCK_RULES_FILE"
  for pair in "$@"; do
    echo "$pair" >> "$MOCK_RULES_FILE"
  done
  local rules_file="$MOCK_RULES_FILE"

  eval "aws() {
    case \"\$*\" in
      *list-resource-record-sets*)
        echo 'None'
        return 0
        ;;
      *describe-load-balancers*--names*)
        local name=''
        local prev=''
        for arg in \"\$@\"; do
          if [ \"\$prev\" = '--names' ]; then name=\"\$arg\"; fi
          prev=\"\$arg\"
        done
        if ! grep -q \"^\${name} \" '${rules_file}' 2>/dev/null; then
          return 1
        fi
        echo \"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/\${name}/abc\"
        return 0
        ;;
      *describe-listeners*)
        local lb_arn=''
        local prev=''
        for arg in \"\$@\"; do
          if [ \"\$prev\" = '--load-balancer-arn' ]; then lb_arn=\"\$arg\"; fi
          prev=\"\$arg\"
        done
        local alb_name=\$(echo \"\$lb_arn\" | sed 's|.*/app/||;s|/.*||')
        echo \"arn:aws:elasticloadbalancing:us-east-1:123:listener/app/\${alb_name}/abc/def\"
        return 0
        ;;
      *describe-rules*)
        local listener_arn=''
        local prev=''
        for arg in \"\$@\"; do
          if [ \"\$prev\" = '--listener-arn' ]; then listener_arn=\"\$arg\"; fi
          prev=\"\$arg\"
        done
        local alb_name=\$(echo \"\$listener_arn\" | sed 's|.*/app/||;s|/.*||')
        local count=\$(grep \"^\${alb_name} \" '${rules_file}' | awk '{print \$2}')
        if [ -z \"\$count\" ]; then
          return 1
        fi
        local rules='{\"Rules\": [{\"IsDefault\": true}'
        local i=0
        while [ \$i -lt \$count ]; do
          rules=\"\${rules}, {\\\"IsDefault\\\": false}\"
          i=\$((i + 1))
        done
        rules=\"\${rules}]}\"
        echo \"\$rules\"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }
  export -f aws"
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
# Additional balancers from container-orchestration provider
# =============================================================================
@test "resolve_balancer: reads additional public balancers from container-orchestration" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["container-orchestration"].balancer.additional_public_names = ["co-extra-1"]
  ')
  mock_alb_rules "co-balancer-public 45" "co-extra-1 10"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-extra-1"
}

@test "resolve_balancer: reads additional private balancers from container-orchestration" {
  export INGRESS_VISIBILITY="internal"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["container-orchestration"].balancer.additional_private_names = ["co-priv-extra-1"]
  ')
  mock_alb_rules "co-balancer-private 45" "co-priv-extra-1 10"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-priv-extra-1"
}

@test "resolve_balancer: scope-configurations additional balancers override container-orchestration" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["scope-extra-1"] |
    .providers["container-orchestration"].balancer.additional_public_names = ["co-extra-1"]
  ')
  mock_alb_rules "co-balancer-public 45" "scope-extra-1 10" "co-extra-1 5"

  source "$SCRIPT"

  # scope-configurations wins — co-extra-1 is not even a candidate
  assert_equal "$ALB_NAME" "scope-extra-1"
}

# =============================================================================
# Priority 1: Route53 lookup takes precedence over everything
# =============================================================================
@test "resolve_balancer: uses ALB from Route53 when record exists" {
  export INGRESS_VISIBILITY="internet-facing"
  mock_route53_alb "alb-from-dns"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-from-dns"
}

@test "resolve_balancer: Route53 takes priority over additional balancers config" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1", "alb-extra-2"]
  ')
  mock_route53_alb "alb-from-dns"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-from-dns"
}

@test "resolve_balancer: Route53 takes priority over provider config" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].networking.balancer_public_name = "scope-alb-public"')
  mock_route53_alb "alb-from-dns"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-from-dns"
}

@test "resolve_balancer: logs when using Route53 ALB" {
  export INGRESS_VISIBILITY="internet-facing"
  mock_route53_alb "alb-from-dns"

  run bash -c 'source "$SCRIPT"'

  assert_contains "$output" "📝 Using ALB 'alb-from-dns' from Route53 record for test.nullapps.io"
}

@test "resolve_balancer: falls through to config when Route53 has no record" {
  export INGRESS_VISIBILITY="internet-facing"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

# =============================================================================
# Priority 2: additional balancers — least-loaded selection
# =============================================================================
@test "resolve_balancer: selects ALB with fewest rules from candidates (public)" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1", "alb-extra-2"]
  ')
  mock_alb_rules "co-balancer-public 45" "alb-extra-1 12" "alb-extra-2 30"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-extra-1"
}

@test "resolve_balancer: selects ALB with fewest rules from candidates (private)" {
  export INGRESS_VISIBILITY="internal"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_private_balancers = ["alb-priv-extra-1", "alb-priv-extra-2"]
  ')
  mock_alb_rules "co-balancer-private 50" "alb-priv-extra-1 20" "alb-priv-extra-2 5"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-priv-extra-2"
}

@test "resolve_balancer: keeps default ALB when it has fewest rules" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')
  mock_alb_rules "co-balancer-public 5" "alb-extra-1 30"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

@test "resolve_balancer: logs selected ALB when different from default" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1"]
  ')
  mock_alb_rules "co-balancer-public 45" "alb-extra-1 12"

  run bash -c 'source "$SCRIPT"'

  assert_contains "$output" "📝 Selected ALB 'alb-extra-1' (12 rules) over default 'co-balancer-public'"
}

@test "resolve_balancer: logs candidate balancers list" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1", "alb-extra-2"]
  ')
  mock_alb_rules "co-balancer-public 10" "alb-extra-1 10" "alb-extra-2 10"

  run bash -c 'export LOG_LEVEL=debug; source "$SCRIPT"'

  assert_contains "$output" "🔍 Additional balancers configured, resolving least-loaded ALB..."
  assert_contains "$output" "📋 Candidate balancers: co-balancer-public, alb-extra-1, alb-extra-2"
}

# =============================================================================
# AWS API failure handling
# =============================================================================
@test "resolve_balancer: skips candidate when rule count query fails" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-extra-1", "alb-extra-2"]
  ')
  # alb-extra-1 not in mock → describe-load-balancers returns 1
  mock_alb_rules "co-balancer-public 45" "alb-extra-2 20"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "alb-extra-2"
}

@test "resolve_balancer: warns when a candidate fails" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-broken"]
  ')
  mock_alb_rules "co-balancer-public 10"

  run bash -c 'source "$SCRIPT"'

  assert_contains "$output" "⚠️  Could not query rules for ALB 'alb-broken', skipping"
}

@test "resolve_balancer: keeps default when all candidates fail" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = ["alb-broken-1", "alb-broken-2"]
  ')
  aws() {
    case "$*" in
      *list-resource-record-sets*) echo "None"; return 0 ;;
      *) return 1 ;;
    esac
  }
  export -f aws

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

# =============================================================================
# No additional balancers — no AWS calls for rule counts
# =============================================================================
@test "resolve_balancer: does not calculate when no additional balancers configured" {
  export INGRESS_VISIBILITY="internet-facing"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}

@test "resolve_balancer: handles empty additional balancers array gracefully" {
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].networking.additional_public_balancers = []
  ')

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
  mock_alb_rules "co-balancer-public 10" "alb-extra-1 10" "alb-extra-2 10"

  source "$SCRIPT"

  assert_equal "$ALB_NAME" "co-balancer-public"
}
