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
	unset NAMING_MAX_LENGTH

	kubectl() { echo '{"apiVersion":"v1","kind":"List","items":[]}'; }
}

@test "qualified: renders the normal deployment name" {
	export NAMING_STRATEGY=qualified
	names="$(np_naming_resolve)"
	run jq -r .deployment <<< "$names"
	assert_equal "$output" "checkout-api-production-789012"
}

@test "qualified: renders hpa, pdb and secret from the same base" {
	export NAMING_STRATEGY=qualified
	names="$(np_naming_resolve)"
	run jq -r '.hpa, .pdb, .secret, .secret_files' <<< "$names"
	assert_equal "$(echo "$output" | sed -n 1p)" "hpa-checkout-api-production-789012"
	assert_equal "$(echo "$output" | sed -n 2p)" "pdb-checkout-api-production-789012"
	assert_equal "$(echo "$output" | sed -n 3p)" "checkout-api-production-789012-env"
	assert_equal "$(echo "$output" | sed -n 4p)" "checkout-api-production-789012-files"
}

@test "qualified: drops visibility from the scope ingress name" {
	export NAMING_STRATEGY=qualified
	kubectl() { echo ""; }
	names="$(np_naming_resolve)"
	run jq -r .scope_ingress <<< "$names"
	assert_equal "$output" "checkout-api-production-123456"
}

@test "qualified: keeps the long case within the deployment budget" {
	export NAMING_STRATEGY=qualified
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json")"
	names="$(np_naming_resolve)"
	run jq -r .deployment <<< "$names"
	assert_equal "$output" "customer-notificati-production-canary-e-789012"
	[ "${#output}" -le 46 ]
}

@test "qualified: keeps the generated pod name within 63 characters" {
	export NAMING_STRATEGY=qualified
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json")"
	names="$(np_naming_resolve)"
	run jq -r .deployment <<< "$names"
	[ "$((${#output} + 17))" -le 63 ]
}

@test "qualified: keeps the scheduled_task cronjob within 52 characters" {
	export NAMING_STRATEGY=qualified
	export NAMING_MAX_LENGTH=43
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json")"
	names="$(np_naming_resolve)"
	run jq -r .cronjob <<< "$names"
	[ "${#output}" -le 52 ]
}

@test "qualified: leaves deployment fields empty without a deployment id" {
	export NAMING_STRATEGY=qualified
	export CONTEXT="$(echo "$CONTEXT" | jq 'del(.deployment)')"
	names="$(np_naming_resolve)"
	run jq -r .deployment <<< "$names"
	assert_equal "$output" ""
}

@test "qualified: NAMING_MAX_LENGTH from the scope-configurations provider overrides the default" {
	export NAMING_STRATEGY=qualified
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json" \
		| jq '.providers["scope-configurations"].naming.max_length = "30"')"
	export NAMING_MAX_LENGTH="$(get_config_value \
		--provider '.providers["scope-configurations"].naming.max_length' \
		--provider '.providers["container-orchestration"].naming.max_length' \
		--env NAMING_MAX_LENGTH \
		--default "46")"
	names="$(np_naming_resolve)"
	run jq -r .deployment <<< "$names"
	assert_equal "$output" "customer-no-production-789012"
	[ "${#output}" -le 30 ]
}
