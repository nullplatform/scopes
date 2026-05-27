#!/usr/bin/env bats
# =============================================================================
# Unit tests for networking/autocreate_alb
# =============================================================================

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"

	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log

	source "$PROJECT_ROOT/k8s/utils/get_config_value"

	export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/autocreate_alb"
	export REGION="us-east-1"
	export INGRESS_VISIBILITY="internet-facing"
	export K8S_NAMESPACE="test-ns"
	export SERVICE_PATH="$PROJECT_ROOT/k8s"
	export ALB_AUTOCREATE_TIMEOUT_SECONDS="2"

	export CONTEXT='{
		"scope": { "id": "scope-1", "slug": "scope-1" },
		"namespace": { "id": "ns-1", "slug": "ns-1" },
		"application": { "id": "app-1", "slug": "app-1" },
		"account": { "id": "acc-1", "slug": "acc-1" },
		"deployment": { "id": "dep-1" },
		"providers": {
			"container-orchestration": {}
		}
	}'

	# Mocks: each test overrides as needed.
	gomplate() { return 0; }
	export -f gomplate
	kubectl() { return 0; }
	export -f kubectl
	aws() { return 1; }
	export -f aws

	# Tracks calls for assertions.
	export CALL_LOG_FILE="$(mktemp)"
}

teardown() {
	unset -f log gomplate kubectl aws get_config_value
	rm -f "$CALL_LOG_FILE"
	unset AUTOCREATED_ALB_NAME
}

# Records each invocation of a mocked binary into CALL_LOG_FILE so tests can
# assert against the sequence of calls.
record_call() {
	echo "$@" >> "$CALL_LOG_FILE"
}

# =============================================================================
# Name generation
# =============================================================================
@test "autocreate_alb: generates ALB name with prefix and visibility short form" {
	# Mock AWS so describe-load-balancers reports active immediately.
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/nullplatform-auto-public-abc123/x","State":{"Code":"active"}}]}'; return 0 ;;
			*add-tags*) return 0 ;;
			*) return 1 ;;
		esac
	}
	export -f aws

	source "$SCRIPT"

	# Length and prefix
	[[ "$AUTOCREATED_ALB_NAME" =~ ^nullplatform-auto-public-[a-f0-9]{6}$ ]]
}

@test "autocreate_alb: uses private short form for internal visibility" {
	export INGRESS_VISIBILITY="internal"
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/x/y","State":{"Code":"active"}}]}'; return 0 ;;
			*add-tags*) return 0 ;;
			*) return 1 ;;
		esac
	}
	export -f aws

	source "$SCRIPT"

	[[ "$AUTOCREATED_ALB_NAME" =~ ^nullplatform-auto-private-[a-f0-9]{6}$ ]]
}

@test "autocreate_alb: respects custom name prefix from env" {
	export ALB_AUTOCREATE_NAME_PREFIX="custom-prefix-"
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/x/y","State":{"Code":"active"}}]}'; return 0 ;;
			*add-tags*) return 0 ;;
			*) return 1 ;;
		esac
	}
	export -f aws

	source "$SCRIPT"

	[[ "$AUTOCREATED_ALB_NAME" =~ ^custom-prefix-public- ]]
}

# =============================================================================
# Ingress dummy application
# =============================================================================
@test "autocreate_alb: renders and applies the dummy ingress before polling" {
	gomplate() { record_call "gomplate $*"; return 0; }
	export -f gomplate
	kubectl() { record_call "kubectl $*"; return 0; }
	export -f kubectl
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/x/y","State":{"Code":"active"}}]}'; return 0 ;;
			*add-tags*) return 0 ;;
			*) return 1 ;;
		esac
	}
	export -f aws

	source "$SCRIPT"

	# Both gomplate and kubectl must have been invoked.
	grep -q "gomplate" "$CALL_LOG_FILE"
	grep -q "kubectl apply" "$CALL_LOG_FILE"
}

@test "autocreate_alb: fails if gomplate render fails" {
	gomplate() { return 1; }
	export -f gomplate

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "Failed to render ingress-dummy template"
}

@test "autocreate_alb: fails if kubectl apply fails" {
	kubectl() { return 1; }
	export -f kubectl

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "Failed to apply ingress-dummy"
}

# =============================================================================
# Polling for active state
# =============================================================================
@test "autocreate_alb: returns success when ALB becomes active within timeout" {
	# describe-load-balancers returns active state immediately.
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/x/y","State":{"Code":"active"}}]}'; return 0 ;;
			*add-tags*) return 0 ;;
			*) return 1 ;;
		esac
	}
	export -f aws

	source "$SCRIPT"

	[ -n "$AUTOCREATED_ALB_NAME" ]
}

@test "autocreate_alb: exits non-zero when ALB never reaches active state (timeout)" {
	export ALB_AUTOCREATE_TIMEOUT_SECONDS="1"
	# Always return provisioning state, never 'active'.
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/x/y","State":{"Code":"provisioning"}}]}'; return 0 ;;
			*) return 1 ;;
		esac
	}
	export -f aws

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "Timed out"
}

@test "autocreate_alb: exits non-zero when ALB reaches 'failed' state" {
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/x/y","State":{"Code":"failed"}}]}'; return 0 ;;
			*) return 1 ;;
		esac
	}
	export -f aws

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "reached state 'failed'"
}

# =============================================================================
# Tagging
# =============================================================================
@test "autocreate_alb: tags the ALB with managed-by, visibility and scope-id" {
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/x/y","State":{"Code":"active"}}]}'; return 0 ;;
			*add-tags*)
				record_call "aws $*"
				return 0
				;;
			*) return 1 ;;
		esac
	}
	export -f aws

	source "$SCRIPT"

	grep -q "nullplatform:managed-by,Value=autocreate" "$CALL_LOG_FILE"
	grep -q "nullplatform:visibility,Value=internet-facing" "$CALL_LOG_FILE"
	grep -q "nullplatform:created-by-scope-id,Value=scope-1" "$CALL_LOG_FILE"
}

@test "autocreate_alb: tagging failure does not fail the script (warn only)" {
	aws() {
		case "$*" in
			*describe-load-balancers*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/x/y","State":{"Code":"active"}}]}'; return 0 ;;
			*add-tags*) return 1 ;;
			*) return 1 ;;
		esac
	}
	export -f aws

	source "$SCRIPT"

	# Script still exports the new ALB name even though tagging warned.
	[ -n "$AUTOCREATED_ALB_NAME" ]
}

# =============================================================================
# Timeout validation
# =============================================================================
@test "autocreate_alb: rejects non-numeric timeout" {
	export ALB_AUTOCREATE_TIMEOUT_SECONDS="abc"

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "must be a positive integer"
}

# =============================================================================
# Name prefix validation
# =============================================================================
@test "autocreate_alb: rejects prefix containing uppercase" {
	export ALB_AUTOCREATE_NAME_PREFIX="Bad-Prefix-"

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "must match"
}

@test "autocreate_alb: rejects prefix containing colon (YAML injection vector)" {
	export ALB_AUTOCREATE_NAME_PREFIX="bad:prefix"

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "must match"
}

@test "autocreate_alb: rejects prefix longer than 18 chars" {
	export ALB_AUTOCREATE_NAME_PREFIX="this-prefix-is-way-too-long-"

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "18 chars"
}
