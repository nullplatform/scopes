#!/usr/bin/env bats
# =============================================================================
# Unit tests for validate_alb_target_group_capacity
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  source "$PROJECT_ROOT/k8s/utils/get_config_value"

  export SCRIPT="$PROJECT_ROOT/k8s/deployment/validate_alb_target_group_capacity"

  export ALB_NAME="k8s-nullplatform-internet-facing"
  export REGION="us-east-1"
  export ALB_MAX_TARGET_GROUPS="98"
  export ALB_MAX_LISTENERS="48"
  export DNS_TYPE="route53"

  # Base CONTEXT
  export CONTEXT='{
    "providers": {}
  }'

  # Mock aws - default: ALB with 40 target groups and 10 listeners
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/k8s-nullplatform-internet-facing/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "40"
        return 0
        ;;
      *"describe-listeners"*)
        echo "10"
        return 0
        ;;
    esac
  }
  export -f aws
}

teardown() {
  unset -f aws
}

# =============================================================================
# Success flow
# =============================================================================
@test "validate_alb_target_group_capacity: success when under capacity" {
  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Validating ALB target group capacity for 'k8s-nullplatform-internet-facing'..."
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 40 target groups (max: 98)"
  assert_contains "$output" "✅ ALB target group capacity validated: 40/98"
}

@test "validate_alb_target_group_capacity: displays debug info" {
  export LOG_LEVEL="debug"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB: k8s-nullplatform-internet-facing | Region: us-east-1 | Max target groups: 98"
  assert_contains "$output" "📋 ALB ARN: arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/k8s-nullplatform-internet-facing/abc123"
}

# =============================================================================
# Capacity exceeded
# =============================================================================
@test "validate_alb_target_group_capacity: fails when at capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "98"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached target group capacity: 98/98"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Too many services or deployments are attached to this ALB"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Remove unused deployments or services from the ALB"
  assert_contains "$output" "Increase ALB_MAX_TARGET_GROUPS in values.yaml or scope-configurations provider (AWS limit is 100)"
  assert_contains "$output" "Request an AWS service quota increase for target groups per ALB"
  assert_contains "$output" "Consider using a separate ALB for additional deployments"
}

@test "validate_alb_target_group_capacity: fails when over capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "100"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached target group capacity: 100/98"
}

# =============================================================================
# Configuration via get_config_value
# =============================================================================
@test "validate_alb_target_group_capacity: uses default ALB_MAX_TARGET_GROUPS of 98" {
  unset ALB_MAX_TARGET_GROUPS

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 40 target groups (max: 98)"
}

@test "validate_alb_target_group_capacity: ALB_MAX_TARGET_GROUPS from env var" {
  export ALB_MAX_TARGET_GROUPS="30"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached target group capacity: 40/30"
}

@test "validate_alb_target_group_capacity: ALB_MAX_TARGET_GROUPS from scope-configurations provider" {
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_max_target_groups":"30"}}}}'
  export ALB_MAX_TARGET_GROUPS="98"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached target group capacity: 40/30"
}

@test "validate_alb_target_group_capacity: ALB_MAX_TARGET_GROUPS from container-orchestration provider" {
  export CONTEXT='{"providers":{"container-orchestration":{"balancer":{"alb_max_target_groups":"30"}}}}'
  export ALB_MAX_TARGET_GROUPS="98"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached target group capacity: 40/30"
}

@test "validate_alb_target_group_capacity: scope-configurations takes priority over container-orchestration" {
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_max_target_groups":"100"}},"container-orchestration":{"balancer":{"alb_max_target_groups":"30"}}}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 40 target groups (max: 100)"
}

@test "validate_alb_target_group_capacity: provider takes priority over env var" {
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_max_target_groups":"100"}}}}'
  export ALB_MAX_TARGET_GROUPS="30"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 40 target groups (max: 100)"
  assert_contains "$output" "✅ ALB target group capacity validated: 40/100"
}

# =============================================================================
# AWS API errors
# =============================================================================
@test "validate_alb_target_group_capacity: fails when describe-load-balancers fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "An error occurred (LoadBalancerNotFound)" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to find load balancer 'k8s-nullplatform-internet-facing' in region 'us-east-1'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The load balancer may not exist or the agent lacks permissions"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify the ALB exists: aws elbv2 describe-load-balancers --names k8s-nullplatform-internet-facing --region us-east-1"
  assert_contains "$output" "Check IAM permissions for elbv2:DescribeLoadBalancers"
}

@test "validate_alb_target_group_capacity: fails when ALB ARN is None" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "None"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Load balancer 'k8s-nullplatform-internet-facing' not found in region 'us-east-1'"
}

@test "validate_alb_target_group_capacity: fails when describe-target-groups fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "Access Denied" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to describe target groups for ALB 'k8s-nullplatform-internet-facing'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The agent may lack permissions to describe target groups"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check IAM permissions for elbv2:DescribeTargetGroups"
}

# =============================================================================
# Edge cases
# =============================================================================
@test "validate_alb_target_group_capacity: handles zero target groups" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "0"
        return 0
        ;;
      *"describe-listeners"*)
        echo "10"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 0 target groups (max: 98)"
  assert_contains "$output" "✅ ALB target group capacity validated: 0/98"
}

@test "validate_alb_target_group_capacity: passes at exactly one below capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "97"
        return 0
        ;;
      *"describe-listeners"*)
        echo "10"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "✅ ALB target group capacity validated: 97/98"
}

@test "validate_alb_target_group_capacity: fails when target group count is non-numeric" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "WARNING: something unexpected"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Unexpected non-numeric target group count from ALB"
  assert_contains "$output" "📋 ALB ARN: arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
  assert_contains "$output" "📋 Received value: WARNING: something unexpected"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The AWS CLI returned an unexpected response format"
}

@test "validate_alb_target_group_capacity: fails when ALB_MAX_TARGET_GROUPS is non-numeric" {
  export ALB_MAX_TARGET_GROUPS="abc"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB_MAX_TARGET_GROUPS must be a numeric value, got: 'abc'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Set a numeric value in values.yaml or scope-configurations provider"
}

@test "validate_alb_target_group_capacity: empty ALB ARN response triggers error" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo ""
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Load balancer 'k8s-nullplatform-internet-facing' not found in region 'us-east-1'"
}

# =============================================================================
# DNS_TYPE guard
# =============================================================================
@test "validate_alb_target_group_capacity: skips when DNS_TYPE is external_dns" {
  export DNS_TYPE="external_dns"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  [[ "$output" != *"🔍 Validating ALB target group capacity"* ]]
}

@test "validate_alb_target_group_capacity: skips when DNS_TYPE is azure" {
  export DNS_TYPE="azure"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  [[ "$output" != *"🔍 Validating ALB target group capacity"* ]]
}

@test "validate_alb_target_group_capacity: skips with debug message for non-route53 DNS" {
  export DNS_TYPE="external_dns"
  export LOG_LEVEL="debug"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "DNS type is 'external_dns', ALB target group validation only applies to route53, skipping"
}

@test "validate_alb_target_group_capacity: runs when DNS_TYPE is route53" {
  export DNS_TYPE="route53"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Validating ALB target group capacity for 'k8s-nullplatform-internet-facing'..."
}

# =============================================================================
# Listener capacity (CLIEN-739)
# =============================================================================
@test "validate_alb_target_group_capacity: success message includes listener capacity" {
  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 10 listeners (max: 48)"
  assert_contains "$output" "✅ ALB listener capacity validated: 10/48"
}

@test "validate_alb_target_group_capacity: fails when listener count is at capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "40"
        return 0
        ;;
      *"describe-listeners"*)
        echo "48"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached listener capacity: 48/48"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Too many scopes with additional_ports are attached to this ALB"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Reduce additional_ports across scopes sharing this ALB"
  assert_contains "$output" "Increase ALB_MAX_LISTENERS in values.yaml or scope-configurations provider (AWS limit is 50)"
  assert_contains "$output" "Request an AWS service quota increase for listeners per ALB"
}

@test "validate_alb_target_group_capacity: fails when listener count is over capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "40"
        return 0
        ;;
      *"describe-listeners"*)
        echo "50"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached listener capacity: 50/48"
}

@test "validate_alb_target_group_capacity: passes at exactly one below listener capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "40"
        return 0
        ;;
      *"describe-listeners"*)
        echo "47"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "✅ ALB listener capacity validated: 47/48"
}

@test "validate_alb_target_group_capacity: handles zero listeners" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "40"
        return 0
        ;;
      *"describe-listeners"*)
        echo "0"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 0 listeners (max: 48)"
  assert_contains "$output" "✅ ALB listener capacity validated: 0/48"
}

@test "validate_alb_target_group_capacity: uses default ALB_MAX_LISTENERS of 48" {
  unset ALB_MAX_LISTENERS

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 10 listeners (max: 48)"
}

@test "validate_alb_target_group_capacity: ALB_MAX_LISTENERS from env var" {
  export ALB_MAX_LISTENERS="5"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached listener capacity: 10/5"
}

@test "validate_alb_target_group_capacity: ALB_MAX_LISTENERS from scope-configurations provider" {
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_max_listeners":"5"}}}}'
  export ALB_MAX_LISTENERS="48"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached listener capacity: 10/5"
}

@test "validate_alb_target_group_capacity: ALB_MAX_LISTENERS from container-orchestration provider" {
  export CONTEXT='{"providers":{"container-orchestration":{"balancer":{"alb_max_listeners":"5"}}}}'
  export ALB_MAX_LISTENERS="48"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached listener capacity: 10/5"
}

@test "validate_alb_target_group_capacity: fails when describe-listeners fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "40"
        return 0
        ;;
      *"describe-listeners"*)
        echo "Access Denied" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to describe listeners for ALB 'k8s-nullplatform-internet-facing'"
  assert_contains "$output" "Check IAM permissions for elbv2:DescribeListeners"
}

@test "validate_alb_target_group_capacity: fails when listener count is non-numeric" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-target-groups"*)
        echo "40"
        return 0
        ;;
      *"describe-listeners"*)
        echo "WARNING: unexpected"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Unexpected non-numeric listener count from ALB"
  assert_contains "$output" "📋 Received value: WARNING: unexpected"
}

@test "validate_alb_target_group_capacity: fails when ALB_MAX_LISTENERS is non-numeric" {
  export ALB_MAX_LISTENERS="abc"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB_MAX_LISTENERS must be a numeric value, got: 'abc'"
}
