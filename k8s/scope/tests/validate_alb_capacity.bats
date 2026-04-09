#!/usr/bin/env bats
# =============================================================================
# Unit tests for validate_alb_capacity
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  source "$PROJECT_ROOT/k8s/utils/get_config_value"

  export SCRIPT="$PROJECT_ROOT/k8s/scope/validate_alb_capacity"

  export ALB_NAME="k8s-nullplatform-internet-facing"
  export REGION="us-east-1"
  export ALB_MAX_CAPACITY="75"

  # Base CONTEXT
  export CONTEXT='{
    "providers": {}
  }'

  # Mock aws - default: ALB with 2 listeners, 30 rules each
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/k8s-nullplatform-internet-facing/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/k8s-nullplatform-internet-facing/abc123/listener1 arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/k8s-nullplatform-internet-facing/abc123/listener2"
        return 0
        ;;
      *"describe-rules"*)
        echo "30"
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
@test "validate_alb_capacity: success when under capacity" {
  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Validating ALB capacity for 'k8s-nullplatform-internet-facing'..."
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 60 rules (max capacity: 75)"
  assert_contains "$output" "✅ ALB capacity validated: 60/75 rules"
}

@test "validate_alb_capacity: displays debug info" {
  export LOG_LEVEL="debug"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB: k8s-nullplatform-internet-facing | Region: us-east-1 | Max capacity: 75 rules"
  assert_contains "$output" "📋 ALB ARN: arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/k8s-nullplatform-internet-facing/abc123"
}

@test "validate_alb_capacity: success with single listener" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
        return 0
        ;;
      *"describe-rules"*)
        echo "10"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 10 rules (max capacity: 75)"
  assert_contains "$output" "✅ ALB capacity validated: 10/75 rules"
}

# =============================================================================
# Capacity exceeded
# =============================================================================
@test "validate_alb_capacity: fails when at capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
        return 0
        ;;
      *"describe-rules"*)
        echo "75"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached capacity: 75/75 rules"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Too many scopes or ingress rules are configured on this ALB"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Remove unused scopes or ingress rules from the ALB"
  assert_contains "$output" "Increase ALB_MAX_CAPACITY in values.yaml or container-orchestration provider (AWS limit is 100 per listener)"
  assert_contains "$output" "Request an AWS service quota increase for rules per ALB listener"
  assert_contains "$output" "Consider using a separate ALB for additional scopes"
}

@test "validate_alb_capacity: fails when over capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
        return 0
        ;;
      *"describe-rules"*)
        echo "90"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached capacity: 90/75 rules"
}

# =============================================================================
# Configuration via get_config_value
# =============================================================================
@test "validate_alb_capacity: uses default ALB_MAX_CAPACITY of 75" {
  unset ALB_MAX_CAPACITY

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 60 rules (max capacity: 75)"
}

@test "validate_alb_capacity: ALB_MAX_CAPACITY from env var" {
  export ALB_MAX_CAPACITY="50"

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached capacity: 60/50 rules"
}

@test "validate_alb_capacity: ALB_MAX_CAPACITY from scope-configurations provider" {
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_max_capacity":"50"}}}}'
  export ALB_MAX_CAPACITY="75"

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached capacity: 60/50 rules"
}

@test "validate_alb_capacity: provider takes priority over env var" {
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_max_capacity":"100"}}}}'
  export ALB_MAX_CAPACITY="50"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 60 rules (max capacity: 100)"
  assert_contains "$output" "✅ ALB capacity validated: 60/100 rules"
}

@test "validate_alb_capacity: ALB_MAX_CAPACITY from container-orchestration provider" {
  export CONTEXT='{"providers":{"container-orchestration":{"balancer":{"alb_capacity_threshold":"50"}}}}'
  export ALB_MAX_CAPACITY="75"

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB 'k8s-nullplatform-internet-facing' has reached capacity: 60/50 rules"
}

@test "validate_alb_capacity: scope-configurations takes priority over container-orchestration" {
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_max_capacity":"100"}},"container-orchestration":{"balancer":{"alb_capacity_threshold":"50"}}}}'

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 60 rules (max capacity: 100)"
}

# =============================================================================
# AWS API errors
# =============================================================================
@test "validate_alb_capacity: fails when describe-load-balancers fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "An error occurred (LoadBalancerNotFound)" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to find load balancer 'k8s-nullplatform-internet-facing' in region 'us-east-1'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The load balancer may not exist or the agent lacks permissions"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify the ALB exists: aws elbv2 describe-load-balancers --names k8s-nullplatform-internet-facing --region us-east-1"
  assert_contains "$output" "Check IAM permissions for elbv2:DescribeLoadBalancers"
}

@test "validate_alb_capacity: fails when ALB ARN is None" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "None"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Load balancer 'k8s-nullplatform-internet-facing' not found in region 'us-east-1'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The load balancer name may be incorrect or it was deleted"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "List available ALBs: aws elbv2 describe-load-balancers --region us-east-1"
  assert_contains "$output" "Check the balancer name in values.yaml or scope-configurations provider"
}

@test "validate_alb_capacity: fails when describe-listeners fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "Access Denied" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to describe listeners for ALB 'k8s-nullplatform-internet-facing'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The agent may lack permissions to describe listeners"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check IAM permissions for elbv2:DescribeListeners"
}

@test "validate_alb_capacity: skips when no listeners found" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "None"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "⚠️  No listeners found on ALB 'k8s-nullplatform-internet-facing', skipping capacity check"
}

@test "validate_alb_capacity: fails when describe-rules fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
        return 0
        ;;
      *"describe-rules"*)
        echo "Access Denied" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to describe rules for listener"
  assert_contains "$output" "📋 Listener ARN: arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The agent may lack permissions to describe rules"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check IAM permissions for elbv2:DescribeRules"
}

# =============================================================================
# Edge cases
# =============================================================================
@test "validate_alb_capacity: handles zero rules" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
        return 0
        ;;
      *"describe-rules"*)
        echo "0"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "📋 ALB 'k8s-nullplatform-internet-facing' has 0 rules (max capacity: 75)"
  assert_contains "$output" "✅ ALB capacity validated: 0/75 rules"
}

@test "validate_alb_capacity: passes at exactly one below capacity" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
        return 0
        ;;
      *"describe-rules"*)
        echo "74"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "✅ ALB capacity validated: 74/75 rules"
}

@test "validate_alb_capacity: fails when rule count is non-numeric" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *"describe-listeners"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
        return 0
        ;;
      *"describe-rules"*)
        echo "WARNING: something unexpected"
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Unexpected non-numeric rule count from listener"
  assert_contains "$output" "📋 Listener ARN: arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
  assert_contains "$output" "📋 Received value: WARNING: something unexpected"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The AWS CLI returned an unexpected response format"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify AWS CLI version and credentials are correct"
}

@test "validate_alb_capacity: fails when ALB_MAX_CAPACITY is non-numeric" {
  export ALB_MAX_CAPACITY="abc"

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ ALB_MAX_CAPACITY must be a numeric value, got: 'abc'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Set a numeric value in values.yaml or scope-configurations provider"
}

@test "validate_alb_capacity: empty ALB ARN response triggers error" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*)
        echo ""
        return 0
        ;;
    esac
  }
  export -f aws

  run bash "$SCRIPT"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Load balancer 'k8s-nullplatform-internet-facing' not found in region 'us-east-1'"
}
