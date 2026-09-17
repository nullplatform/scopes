#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log
	source "$PROJECT_ROOT/k8s/utils/get_config_value"
	source "$PROJECT_ROOT/k8s/naming/resolve_names"

	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal.json")"
	unset NAMING_STRATEGY
}

@test "np_naming_resolve: ids reproduces today's deployment name" {
	names="$(np_naming_resolve)"
	run jq -r '.deployment' <<< "$names"
	assert_equal "$output" "d-123456-789012"
}

@test "np_naming_resolve: ids reproduces today's hpa, pdb and secret names" {
	names="$(np_naming_resolve)"
	run jq -r '.hpa, .pdb, .secret, .secret_files' <<< "$names"
	assert_equal "$(echo "$output" | sed -n 1p)" "hpa-d-123456-789012"
	assert_equal "$(echo "$output" | sed -n 2p)" "pdb-d-123456-789012"
	assert_equal "$(echo "$output" | sed -n 3p)" "s-123456-d-789012"
	assert_equal "$(echo "$output" | sed -n 4p)" "s-123456-d-789012-files"
}

@test "np_naming_resolve: ids reproduces today's scope ingress name with visibility" {
	names="$(np_naming_resolve)"
	run jq -r '.scope_ingress' <<< "$names"
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}

@test "np_naming_resolve: ids reproduces today's dns-endpoint truncation" {
	names="$(np_naming_resolve)"
	run jq -r '.scope_dns' <<< "$names"
	assert_equal "$output" "k8s-checkout-api-production-123456-dns"
}

@test "np_naming_resolve: ids keeps the serving-cert name separate from the ingress base" {
	names="$(np_naming_resolve)"
	run jq -r '.serving_cert, .scope_ingress' <<< "$names"
	assert_equal "$(echo "$output" | sed -n 1p)" "d-123456"
	assert_equal "$(echo "$output" | sed -n 2p)" "k-8-s-production-123456-internet-facing"
}

@test "np_naming_resolve: leaves deployment fields empty without a deployment id" {
	export CONTEXT="$(echo "$CONTEXT" | jq 'del(.deployment)')"
	names="$(np_naming_resolve)"
	run jq -r '.deployment, .hpa, .secret' <<< "$names"
	assert_equal "$(echo "$output" | sed -n 1p)" ""
	assert_equal "$(echo "$output" | sed -n 2p)" ""
	assert_equal "$(echo "$output" | sed -n 3p)" ""
}

@test "np_naming_resolve: still resolves scope names without a deployment id" {
	export CONTEXT="$(echo "$CONTEXT" | jq 'del(.deployment)')"
	names="$(np_naming_resolve)"
	run jq -r '.scope_ingress' <<< "$names"
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}

@test "np_naming_resolve: unset strategy defaults to ids" {
	unset NAMING_STRATEGY
	names="$(np_naming_resolve)"
	run jq -r '.deployment' <<< "$names"
	assert_equal "$output" "d-123456-789012"
}

@test "np_naming_resolve: empty strategy aborts" {
	export NAMING_STRATEGY=""
	run np_naming_resolve
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ NAMING_STRATEGY is set but empty"
	assert_contains "$output" "   • Remove it to use the default 'ids', or set one of: ids, qualified, custom"
}

@test "np_naming_resolve: unrecognised strategy aborts" {
	export NAMING_STRATEGY="readable"
	run np_naming_resolve
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Unknown naming strategy 'readable'"
	assert_contains "$output" "   • Valid strategies: ids, qualified, custom"
}

@test "np_naming_resolve: enriches additional ports with service and ingress names" {
	names="$(np_naming_resolve)"
	run jq -r '.additional_ports[0].service_name, .additional_ports[0].ingress_name' <<< "$names"
	assert_equal "$(echo "$output" | sed -n 1p)" "d-123456-789012-grpc-9090"
	assert_equal "$(echo "$output" | sed -n 2p)" "k-8-s-production-123456-grpc-9090-internet-facing"
}
