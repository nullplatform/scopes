#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/validate_alb_capacity - combined rule + TG check
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export ALB_NAME="k8s-nullplatform-internet-facing"
  export REGION="us-east-1"
  export DNS_TYPE="route53"

  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "domain": "app.example.com",
      "domains": [],
      "capabilities": {}
    },
    "alb_name": "k8s-nullplatform-internet-facing",
    "deployment": {
      "strategy": "rolling"
    }
  }'

  # Default mock: ALB with HTTPS listener, 50 rules, 40 TGs
  get_config_value() {
    local default_val=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --default) default_val="$2"; shift 2 ;;
        *) shift 2 ;;
      esac
    done
    echo "$default_val"
  }
  export -f get_config_value

  aws() {
    case "$*" in
      *describe-load-balancers*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/alb/abc123"
        return 0
        ;;
      *describe-listeners*)
        echo "arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/alb/abc123/listener1"
        return 0
        ;;
      *describe-rules*)
        echo "50"
        return 0
        ;;
      *describe-target-groups*)
        echo "40"
        return 0
        ;;
    esac
    return 0
  }
  export -f aws
}

teardown() {
  unset CONTEXT
}

# =============================================================================
# Success Cases
# =============================================================================
@test "validate_alb_capacity: passes when both rules and TGs are under capacity" {
  run bash -c "
    $(declare -f aws get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "Rule capacity OK"
  assert_contains "$output" "Target group capacity OK"
}

@test "validate_alb_capacity: skips for non-route53 DNS types" {
  run bash -c "
    $(declare -f aws get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='azure' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "ALB capacity validation only applies to route53"
}

# =============================================================================
# Rule capacity failures
# =============================================================================
@test "validate_alb_capacity: fails when rules would exceed capacity" {
  run bash -c "
    aws() {
      case \"\$*\" in
        *describe-load-balancers*) echo 'arn:aws:elbv2:alb/abc'; return 0 ;;
        *describe-listeners*) echo 'arn:aws:elbv2:listener/1'; return 0 ;;
        *describe-rules*) echo '74'; return 0 ;;
        *describe-target-groups*) echo '40'; return 0 ;;
      esac
    }
    export -f aws
    $(declare -f get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "would exceed rule capacity: 74 current + 1 new = 75/75"
}

@test "validate_alb_capacity: estimates rules from domains and additional ports" {
  local ctx='{"scope":{"slug":"app","domain":"a.com","domains":[{"name":"b.com"},{"name":"c.com"}],"capabilities":{"additional_ports":[{"type":"HTTP","port":8081}]}},"alb_name":"alb","deployment":{"strategy":"rolling"}}'

  run bash -c "
    aws() {
      case \"\$*\" in
        *describe-load-balancers*) echo 'arn:alb'; return 0 ;;
        *describe-listeners*) echo 'arn:listener'; return 0 ;;
        *describe-rules*) echo '40'; return 0 ;;
        *describe-target-groups*) echo '40'; return 0 ;;
      esac
    }
    export -f aws
    $(declare -f get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$ctx'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 0 ]
  # 3 domains * (1 + 1 additional port) = 6 rules
  assert_contains "$output" "this scope would add ~6"
}

# =============================================================================
# Target group capacity failures
# =============================================================================
@test "validate_alb_capacity: fails when TGs would exceed capacity" {
  run bash -c "
    aws() {
      case \"\$*\" in
        *describe-load-balancers*) echo 'arn:alb'; return 0 ;;
        *describe-listeners*) echo 'arn:listener'; return 0 ;;
        *describe-rules*) echo '10'; return 0 ;;
        *describe-target-groups*) echo '89'; return 0 ;;
      esac
    }
    export -f aws
    $(declare -f get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "Rule capacity OK"
  assert_contains "$output" "would exceed target group capacity: 89 current + 1 new = 90/90"
}

@test "validate_alb_capacity: estimates 2x TGs for blue-green strategy" {
  local ctx='{"scope":{"slug":"app","domain":"a.com","domains":[],"capabilities":{"additional_ports":[{"type":"HTTP","port":8081}]}},"alb_name":"alb","deployment":{"strategy":"blue_green"}}'

  run bash -c "
    aws() {
      case \"\$*\" in
        *describe-load-balancers*) echo 'arn:alb'; return 0 ;;
        *describe-listeners*) echo 'arn:listener'; return 0 ;;
        *describe-rules*) echo '10'; return 0 ;;
        *describe-target-groups*) echo '10'; return 0 ;;
      esac
    }
    export -f aws
    $(declare -f get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$ctx'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 0 ]
  # (1 + 1 additional port) * 2 = 4 TGs for blue-green
  assert_contains "$output" "this deployment would add ~4"
}

# =============================================================================
# AWS API failures
# =============================================================================
@test "validate_alb_capacity: fails when describe-load-balancers fails" {
  run bash -c "
    aws() { return 1; }
    export -f aws
    $(declare -f get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "Failed to find load balancer"
}

@test "validate_alb_capacity: fails when ALB ARN is None" {
  run bash -c "
    aws() { echo 'None'; return 0; }
    export -f aws
    $(declare -f get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "not found in region"
}

@test "validate_alb_capacity: skips rule check when no HTTPS listener found" {
  run bash -c "
    aws() {
      case \"\$*\" in
        *describe-load-balancers*) echo 'arn:alb'; return 0 ;;
        *describe-listeners*) echo 'None'; return 0 ;;
        *describe-target-groups*) echo '10'; return 0 ;;
      esac
    }
    export -f aws
    $(declare -f get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "No HTTPS (443) listener found"
  assert_contains "$output" "Target group capacity OK"
}

@test "validate_alb_capacity: fails when describe-target-groups fails" {
  run bash -c "
    aws() {
      case \"\$*\" in
        *describe-load-balancers*) echo 'arn:alb'; return 0 ;;
        *describe-listeners*) echo 'arn:listener'; return 0 ;;
        *describe-rules*) echo '10'; return 0 ;;
        *describe-target-groups*) return 1 ;;
      esac
    }
    export -f aws
    $(declare -f get_config_value log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "Rule capacity OK"
  assert_contains "$output" "Failed to describe target groups"
}

# =============================================================================
# Config validation
# =============================================================================
@test "validate_alb_capacity: fails when ALB_MAX_CAPACITY is non-numeric" {
  run bash -c "
    get_config_value() {
      local default_val=''
      while [[ \$# -gt 0 ]]; do
        case \"\$1\" in
          --default) default_val=\"\$2\"; shift 2 ;;
          --env)
            if [[ \"\$2\" == \"ALB_MAX_CAPACITY\" ]]; then
              echo 'abc'; return
            fi
            shift 2 ;;
          *) shift 2 ;;
        esac
      done
      echo \"\$default_val\"
    }
    export -f get_config_value
    $(declare -f aws log)
    export ALB_NAME='$ALB_NAME' REGION='$REGION' DNS_TYPE='$DNS_TYPE' CONTEXT='$CONTEXT'
    export ALB_MAX_CAPACITY='abc'
    source '$BATS_TEST_DIRNAME/../validate_alb_capacity'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "ALB_MAX_CAPACITY must be a numeric value"
}
