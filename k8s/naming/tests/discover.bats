#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log
	source "$PROJECT_ROOT/k8s/utils/get_config_value"
	source "$PROJECT_ROOT/k8s/naming/resolve_names"
	export -f np_naming_discover_blue
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
