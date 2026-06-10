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

	aws() { return 1; }
	export -f aws
}

teardown() {
	unset -f log aws get_config_value
	unset ALB_AUTOCREATED
}

# Builds an aws() mock that returns the given state in a single
# describe-load-balancers --output json response. add-tags returns 0.
mock_aws_state() {
	local state="$1"
	local arn="arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/$ALB_NAME/abc"
	eval "aws() {
		case \"\$*\" in
			*describe-load-balancers*)
				echo '{\"LoadBalancers\":[{\"LoadBalancerArn\":\"${arn}\",\"State\":{\"Code\":\"${state}\"}}]}'
				return 0
				;;
			*add-tags*) return 0 ;;
		esac
		return 1
	}
	export -f aws"
}

# =============================================================================
# Active state
# =============================================================================
@test "wait_for_alb: success path logs full sequence when ALB is already active" {
	mock_aws_state "active"

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "0"
	assert_contains "$output" "⏳ Waiting up to 2s for ALB 'test-alb' to become active..."
	assert_contains "$output" "📋 ALB 'test-alb' state: active"
	assert_contains "$output" "✅ ALB 'test-alb' is active"
}

@test "wait_for_alb: honors timeout value in the initial wait log" {
	export ALB_AUTOCREATE_TIMEOUT_SECONDS="120"
	mock_aws_state "active"

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "0"
	assert_contains "$output" "⏳ Waiting up to 120s for ALB 'test-alb' to become active..."
}

# =============================================================================
# Failed state
# =============================================================================
@test "wait_for_alb: exits with full failure log when ALB reaches state=failed" {
	mock_aws_state "failed"

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "1"
	assert_contains "$output" "⏳ Waiting up to 2s for ALB 'test-alb' to become active..."
	assert_contains "$output" "📋 ALB 'test-alb' state: failed"
	assert_contains "$output" "❌ ALB 'test-alb' reached state 'failed'"
}

# =============================================================================
# Timeout with full diagnostic log
# =============================================================================
@test "wait_for_alb: timeout emits diagnostic causes and fix hints" {
	export ALB_AUTOCREATE_TIMEOUT_SECONDS="1"
	mock_aws_state "provisioning"

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "1"
	assert_contains "$output" "⏳ Waiting up to 1s for ALB 'test-alb' to become active..."
	assert_contains "$output" "📋 ALB 'test-alb' state: provisioning"
	assert_contains "$output" "❌ Timed out after 1s waiting for ALB 'test-alb' to become active"
	assert_contains "$output" "💡 Possible causes:"
	assert_contains "$output" "   The AWS Load Balancer Controller may be slow, mis-configured, or the AWS account may be hitting an ALB quota"
	assert_contains "$output" "🔧 How to fix:"
	assert_contains "$output" "   • Check controller logs: kubectl -n kube-system logs deploy/aws-load-balancer-controller"
	assert_contains "$output" "   • Verify ALB quota: aws service-quotas get-service-quota --service-code elasticloadbalancing --quota-code L-53DA6B97"
}

# =============================================================================
# Heartbeat
# =============================================================================
@test "wait_for_alb: emits heartbeat info log when the wait crosses the threshold" {
	# Shrink both the poll interval and the heartbeat threshold so the test
	# exercises the heartbeat path without sitting through real 30s intervals.
	PATCHED_SCRIPT="$BATS_TEST_TMPDIR/wait_for_alb_patched"
	sed -e 's/^poll_interval=10$/poll_interval=1/' \
	    -e 's/^heartbeat_interval=30$/heartbeat_interval=1/' \
	    "$SCRIPT" > "$PATCHED_SCRIPT"

	export ALB_AUTOCREATE_TIMEOUT_SECONDS="3"
	mock_aws_state "provisioning"

	run bash -c "source '$PATCHED_SCRIPT'"

	# Times out as expected, but we should see at least one heartbeat info log.
	assert_equal "$status" "1"
	assert_contains "$output" "⏳ Still waiting for ALB 'test-alb' to become active (provisioning,"
}

# =============================================================================
# Tagging on autocreate
# =============================================================================
@test "wait_for_alb: tags ALB and logs full tag-success message when ALB_AUTOCREATED=true" {
	export ALB_AUTOCREATED="true"
	mock_aws_state "active"

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "0"
	assert_contains "$output" "⏳ Waiting up to 2s for ALB 'test-alb' to become active..."
	assert_contains "$output" "📋 ALB 'test-alb' state: active"
	assert_contains "$output" "✅ ALB 'test-alb' is active"
	assert_contains "$output" "📋 Tagged ALB 'test-alb' with managed-by=autocreate"
}

@test "wait_for_alb: does not tag (no tag log) when ALB_AUTOCREATED is unset" {
	mock_aws_state "active"

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "0"
	assert_contains "$output" "✅ ALB 'test-alb' is active"
	# No tagging log should appear
	[[ "$output" != *"Tagged ALB"* ]]
	[[ "$output" != *"Could not tag ALB"* ]]
}

@test "wait_for_alb: tag failure logs full warn message but exits 0" {
	export ALB_AUTOCREATED="true"
	local arn="arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/$ALB_NAME/abc"
	eval "aws() {
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

	assert_equal "$status" "0"
	assert_contains "$output" "✅ ALB 'test-alb' is active"
	assert_contains "$output" "⚠️  Could not tag ALB 'test-alb' (audit only — provider registration already succeeded)"
}
