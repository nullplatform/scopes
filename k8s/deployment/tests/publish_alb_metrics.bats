#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PROJECT_ROOT/k8s/deployment/publish_alb_metrics"

  # Default context
  export CONTEXT='{"alb_name":"k8s-nullplatform-internet-facing","region":"us-east-1"}'

  # Default config
  export ALB_METRICS_PUBLISH_ENABLED="true"
  export ALB_METRICS_PUBLISH_TARGET="cloudwatch"

  # Track calls
  export AWS_CALLS_LOG="$BATS_TEST_TMPDIR/aws_calls.log"
  export CURL_CALLS_LOG="$BATS_TEST_TMPDIR/curl_calls.log"

  # Mock aws CLI
  aws() {
    echo "$*" >> "$AWS_CALLS_LOG"
    case "$*" in
      *"describe-load-balancers"*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/k8s-nullplatform-internet-facing/abc123"
        ;;
      *"describe-listeners"*)
        echo '{"Listeners":[{"ListenerArn":"arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/abc/123"}]}'
        ;;
      *"describe-rules"*)
        echo '{"Rules":[{"IsDefault":true},{"IsDefault":false},{"IsDefault":false},{"IsDefault":false}]}'
        ;;
      *"describe-target-groups"*)
        echo '{"TargetGroups":[{},{},{},{},{}]}'
        ;;
      *"put-metric-data"*)
        return 0
        ;;
    esac
  }
  export -f aws

  # Mock curl
  curl() {
    echo "$*" >> "$CURL_CALLS_LOG"
    echo "202"
  }
  export -f curl

  # Mock log function (from k8s/logging)
  log() {
    local level="${1:-info}"
    local message="${2:-}"
    echo "$message"
  }
  export -f log
}

run_script() {
  run bash -c 'source "$SCRIPT"'
}

# =============================================================================
# Disabled / skipped scenarios
# =============================================================================

@test "skips silently when ALB_METRICS_PUBLISH_ENABLED is false" {
  export ALB_METRICS_PUBLISH_ENABLED="false"
  run_script
  assert_equal "$status" "0"
  assert_equal "$output" ""
}

@test "skips silently when ALB_METRICS_PUBLISH_ENABLED is not set" {
  unset ALB_METRICS_PUBLISH_ENABLED
  run_script
  assert_equal "$status" "0"
  assert_equal "$output" ""
}

# =============================================================================
# Error scenarios
# =============================================================================

@test "warns when ALB name not found in context" {
  export CONTEXT='{"region":"us-east-1"}'
  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: ALB name not found in context"
}

@test "warns when ALB name is null in context" {
  export CONTEXT='{"alb_name":null,"region":"us-east-1"}'
  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: ALB name not found in context"
}

@test "warns when ALB not found in AWS" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*) echo "None" ;;
    esac
  }
  export -f aws

  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: could not find ALB"
}

@test "warns when describe-load-balancers fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*) return 1 ;;
    esac
  }
  export -f aws

  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: could not find ALB"
}

@test "warns when describe-listeners fails" {
  aws() {
    case "$*" in
      *"describe-load-balancers"*) echo "arn:aws:elasticloadbalancing:us-east-1:123:lb/abc" ;;
      *"describe-listeners"*) return 1 ;;
    esac
  }
  export -f aws

  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: could not retrieve listeners"
}

# =============================================================================
# CloudWatch success
# =============================================================================

@test "publishes to CloudWatch with correct rule and target group counts" {
  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics published to CloudWatch (rules: 3, target_groups: 5)"
}

@test "CloudWatch put-metric-data uses correct namespace and dimensions" {
  run_script
  local calls=$(cat "$AWS_CALLS_LOG")
  assert_contains "$calls" "nullplatform/ApplicationELB"
  assert_contains "$calls" "k8s-nullplatform-internet-facing"
  assert_contains "$calls" "RuleCount"
  assert_contains "$calls" "TargetGroupCount"
}

@test "warns when CloudWatch put-metric-data fails" {
  aws() {
    echo "$*" >> "$AWS_CALLS_LOG"
    case "$*" in
      *"describe-load-balancers"*) echo "arn:aws:elasticloadbalancing:us-east-1:123:lb/abc" ;;
      *"describe-listeners"*) echo '{"Listeners":[{"ListenerArn":"arn:listener/123"}]}' ;;
      *"describe-rules"*) echo '{"Rules":[{"IsDefault":true}]}' ;;
      *"describe-target-groups"*) echo '{"TargetGroups":[]}' ;;
      *"put-metric-data"*) return 1 ;;
    esac
  }
  export -f aws

  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: failed to publish to CloudWatch"
}

# =============================================================================
# Datadog success
# =============================================================================

@test "publishes to Datadog with correct counts" {
  export ALB_METRICS_PUBLISH_TARGET="datadog"
  export DATADOG_API_KEY="test-api-key"
  export DATADOG_SITE="datadoghq.com"

  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics published to Datadog (rules: 3, target_groups: 5)"
}

@test "Datadog request uses correct endpoint and metric names" {
  export ALB_METRICS_PUBLISH_TARGET="datadog"
  export DATADOG_API_KEY="test-api-key"
  export DATADOG_SITE="datadoghq.eu"

  run_script
  local calls=$(cat "$CURL_CALLS_LOG")
  assert_contains "$calls" "https://api.datadoghq.eu/api/v2/series"
  assert_contains "$calls" "nullplatform.applicationelb.rule_count"
  assert_contains "$calls" "nullplatform.applicationelb.target_group_count"
  assert_contains "$calls" "alb_name:k8s-nullplatform-internet-facing"
}

@test "warns when DATADOG_API_KEY not set" {
  export ALB_METRICS_PUBLISH_TARGET="datadog"
  unset DATADOG_API_KEY

  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: DATADOG_API_KEY not set"
}

@test "warns when Datadog returns non-202" {
  export ALB_METRICS_PUBLISH_TARGET="datadog"
  export DATADOG_API_KEY="test-api-key"

  curl() {
    echo "403"
  }
  export -f curl

  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: failed to publish to Datadog (HTTP 403)"
}

# =============================================================================
# Unknown target
# =============================================================================

@test "warns on unknown metrics target" {
  export ALB_METRICS_PUBLISH_TARGET="prometheus"
  run_script
  assert_equal "$status" "0"
  assert_contains "$output" "ALB metrics: unknown target 'prometheus'"
}

# =============================================================================
# Rule counting logic
# =============================================================================

@test "excludes default rules from count" {
  aws() {
    echo "$*" >> "$AWS_CALLS_LOG"
    case "$*" in
      *"describe-load-balancers"*) echo "arn:aws:elasticloadbalancing:us-east-1:123:lb/abc" ;;
      *"describe-listeners"*) echo '{"Listeners":[{"ListenerArn":"arn:listener/123"}]}' ;;
      *"describe-rules"*) echo '{"Rules":[{"IsDefault":true},{"IsDefault":false}]}' ;;
      *"describe-target-groups"*) echo '{"TargetGroups":[{}]}' ;;
      *"put-metric-data"*) return 0 ;;
    esac
  }
  export -f aws

  run_script
  assert_contains "$output" "rules: 1, target_groups: 1"
}

@test "counts rules across multiple listeners" {
  aws() {
    echo "$*" >> "$AWS_CALLS_LOG"
    case "$*" in
      *"describe-load-balancers"*) echo "arn:aws:elasticloadbalancing:us-east-1:123:lb/abc" ;;
      *"describe-listeners"*) echo '{"Listeners":[{"ListenerArn":"arn:listener/1"},{"ListenerArn":"arn:listener/2"}]}' ;;
      *"describe-rules"*"listener/1"*) echo '{"Rules":[{"IsDefault":true},{"IsDefault":false},{"IsDefault":false}]}' ;;
      *"describe-rules"*"listener/2"*) echo '{"Rules":[{"IsDefault":true},{"IsDefault":false}]}' ;;
      *"describe-rules"*) echo '{"Rules":[{"IsDefault":true},{"IsDefault":false},{"IsDefault":false}]}' ;;
      *"describe-target-groups"*) echo '{"TargetGroups":[{},{}]}' ;;
      *"put-metric-data"*) return 0 ;;
    esac
  }
  export -f aws

  run_script
  assert_contains "$output" "rules: 3, target_groups: 2"
}
