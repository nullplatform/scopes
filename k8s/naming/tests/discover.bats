#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log
	source "$PROJECT_ROOT/k8s/utils/get_config_value"
	source "$PROJECT_ROOT/k8s/naming/resolve_names"
	export -f get_config_value np_name_sanitize np_name_cap np_trim_segments np_trim_name \
		np_name_value np_name_is_fixed np_name_is_known np_naming_validate_pattern \
		np_name_render np_naming_strategy np_naming_resolve np_naming_roles_ids \
		np_naming_emit np_naming_roles_patterned np_naming_lookup np_naming_discover_blue \
		np_naming_discover_scope
	export NP_NAME_PLACEHOLDERS NP_NAME_FIXED_PLACEHOLDERS \
		NP_NAMING_DEPLOYMENT_PATTERN_DEFAULT NP_NAMING_SCOPE_PATTERN_DEFAULT NP_NAMING_SCOPE_BUDGET

	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal.json")"
	unset NAMING_STRATEGY
	unset NAMING_MAX_LENGTH
}

@test "np_naming_lookup: returns the object name for a deployment id" {
	kubectl() { echo "hpa-d-123456-789012"; }
	export -f kubectl
	run np_naming_lookup hpa nullplatform 789012
	assert_equal "$output" "hpa-d-123456-789012"
}

@test "np_naming_lookup: fails and stays silent when nothing matches" {
	kubectl() { echo ""; }
	export -f kubectl
	run np_naming_lookup hpa nullplatform 789012
	[ "$status" -ne 0 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_blue: finds the main service by its main port" {
	kubectl() { cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/svc-ids.json"; }
	export -f kubectl
	run bash -c "np_naming_discover_blue nullplatform 789011 8080 | jq -r .service"
	assert_equal "$output" "d-123456-789011"
}

@test "np_naming_discover_blue: finds a per-port service by its port" {
	kubectl() { cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/svc-ids.json"; }
	export -f kubectl
	run bash -c "np_naming_discover_blue nullplatform 789011 8080 | jq -r '.ports[\"grpc-9090\"]'"
	assert_equal "$output" "d-123456-789011-grpc-9090"
}

@test "np_naming_discover_blue: returns empty fields when nothing matches" {
	kubectl() { echo '{"items":[]}'; }
	export -f kubectl
	run bash -c "np_naming_discover_blue nullplatform 789011 8080 | jq -r .service"
	assert_equal "$output" ""
}

@test "np_naming_discover_blue: returns empty fields when there is no blue deployment" {
	kubectl() { echo '{"items":[]}'; }
	export -f kubectl
	run bash -c "np_naming_discover_blue nullplatform '' 8080 | jq -r .service"
	assert_equal "$output" ""
}

@test "np_naming_discover_blue: finds a blue named by a different strategy" {
	kubectl() { cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/svc-qualified.json"; }
	export -f kubectl
	run bash -c "np_naming_discover_blue nullplatform 789011 8080 | jq -r .service"
	assert_equal "$output" "checkout-api-production-789011"
}

@test "np_naming_discover_scope: returns the existing ingress name" {
	kubectl() { echo "k-8-s-production-123456-internet-facing"; }
	export -f kubectl
	run np_naming_discover_scope nullplatform 123456
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}

@test "qualified: keeps an existing scope ingress name instead of renaming it" {
	export NAMING_STRATEGY=qualified
	kubectl() { echo "k-8-s-production-123456-internet-facing"; }
	export -f kubectl
	run bash -c "np_naming_resolve 2>/dev/null | jq -r .scope_ingress"
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}

@test "qualified: computes a scope ingress name when none exists" {
	export NAMING_STRATEGY=qualified
	kubectl() { echo ""; }
	export -f kubectl
	run bash -c "np_naming_resolve | jq -r .scope_ingress"
	assert_equal "$output" "checkout-api-production-123456"
}

@test "qualified: a frozen ingress name does not freeze the deployment name" {
	export NAMING_STRATEGY=qualified
	kubectl() { echo "k-8-s-production-123456-internet-facing"; }
	export -f kubectl
	run bash -c "np_naming_resolve 2>/dev/null | jq -r .deployment"
	assert_equal "$output" "checkout-api-production-789012"
}

@test "qualified: keeping an existing name is logged" {
	export NAMING_STRATEGY=qualified
	kubectl() { echo "k-8-s-production-123456-internet-facing"; }
	export -f kubectl
	run np_naming_resolve
	assert_contains "$output" "✅ Keeping the existing scope object name 'k-8-s-production-123456-internet-facing'"
}

@test "qualified: the resolved JSON on stdout stays valid when an existing name is kept" {
	export NAMING_STRATEGY=qualified
	kubectl() { echo "k-8-s-production-123456-internet-facing"; }
	export -f kubectl
	run bash -c "np_naming_resolve 2>/dev/null | jq -e ."
	[ "$status" -eq 0 ]
}
