#!/usr/bin/env bats
# =============================================================================
# Unit tests for networking/wait_for_alb
# =============================================================================

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"

	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log

	source "$PROJECT_ROOT/k8s/utils/get_config_value"
	export -f get_config_value

	export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/wait_for_alb"
	export REGION="us-east-1"
	export ALB_NAME="test-alb"
	export INGRESS_VISIBILITY="internet-facing"
	export ALB_AUTOCREATE_TIMEOUT_SECONDS="2"

	export CONTEXT='{
		"scope": { "id": "scope-1" },
		"providers": { "container-orchestration": {} }
	}'

	export CALL_LOG_FILE="$(mktemp)"

	aws() { return 1; }
	export -f aws
}

teardown() {
	unset -f log aws get_config_value
	rm -f "$CALL_LOG_FILE"
	unset ALB_AUTOCREATED
}

# Mocks describe-load-balancers + add-tags. The state arg controls what the
# describe response reports.
mock_aws_state() {
	local state="$1"
	local arn="arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/$ALB_NAME/abc"
	eval "aws() {
		echo \"aws \$*\" >> '$CALL_LOG_FILE'
		case \"\$*\" in
			*describe-load-balancers*)
				echo '{\"LoadBalancers\":[{\"LoadBalancerArn\":\"${arn}\",\"State\":{\"Code\":\"${state}\"}}]}'
				return 0
				;;
			*add-tags*)
				return 0
				;;
		esac
		return 1
	}
	export -f aws"
}

# =============================================================================
# Active state
# =============================================================================
@test "wait_for_alb: returns success when ALB is already active" {
	mock_aws_state "active"

	run bash -c 'source "$SCRIPT"'

	[ "$status" -eq 0 ]
	assert_contains "$output" "is active"
}

# =============================================================================
# Failed state
# =============================================================================
@test "wait_for_alb: exits when ALB reaches state=failed" {
	mock_aws_state "failed"

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "reached state 'failed'"
}

# =============================================================================
# Timeout
# =============================================================================
@test "wait_for_alb: exits when ALB never reaches active within timeout" {
	export ALB_AUTOCREATE_TIMEOUT_SECONDS="1"
	mock_aws_state "provisioning"

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "Timed out"
}

# =============================================================================
# Tagging on autocreate
# =============================================================================
@test "wait_for_alb: tags the ALB when ALB_AUTOCREATED=true" {
	export ALB_AUTOCREATED="true"
	mock_aws_state "active"

	source "$SCRIPT"

	grep -q "add-tags" "$CALL_LOG_FILE"
	grep -q "nullplatform:managed-by,Value=autocreate" "$CALL_LOG_FILE"
	grep -q "nullplatform:visibility,Value=internet-facing" "$CALL_LOG_FILE"
	grep -q "nullplatform:created-by-scope-id,Value=scope-1" "$CALL_LOG_FILE"
}

@test "wait_for_alb: does not tag when ALB_AUTOCREATED is unset" {
	mock_aws_state "active"

	source "$SCRIPT"

	! grep -q "add-tags" "$CALL_LOG_FILE"
}

@test "wait_for_alb: tagging failure warns but does not fail the script" {
	export ALB_AUTOCREATED="true"
	local arn="arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/$ALB_NAME/abc"
	eval "aws() {
		echo \"aws \$*\" >> '$CALL_LOG_FILE'
		case \"\$*\" in
			*describe-load-balancers*)
				echo '{\"LoadBalancers\":[{\"LoadBalancerArn\":\"${arn}\",\"State\":{\"Code\":\"active\"}}]}'
				return 0
				;;
			*add-tags*) return 1 ;;
		esac
		return 1
	}
	export -f aws"

	run bash -c 'source "$SCRIPT"'

	[ "$status" -eq 0 ]
	assert_contains "$output" "audit only"
}
