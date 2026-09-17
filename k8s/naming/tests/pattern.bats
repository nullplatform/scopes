#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log
	source "$PROJECT_ROOT/k8s/naming/resolve_names"

	export NP_NAME_APPLICATION="checkout-api"
	export NP_NAME_SCOPE="production"
	export NP_NAME_NAMESPACE="payments"
	export NP_NAME_ACCOUNT="acme"
	export NP_NAME_DEPLOYMENT_ID="789012"
	export NP_NAME_SCOPE_ID="123456"
	export NP_NAME_APPLICATION_ID="111"
	export NP_NAME_NAMESPACE_ID="11"
}

@test "np_naming_validate_pattern: accepts a pattern carrying its discriminant" {
	run np_naming_validate_pattern "{application}-{scope}-{deployment_id}" "deployment_id"
	[ "$status" -eq 0 ]
}

@test "np_naming_validate_pattern: rejects a pattern without its discriminant" {
	run np_naming_validate_pattern "{application}-{scope}" "deployment_id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{application}-{scope}' does not contain {deployment_id}"
	assert_contains "$output" "💡 Possible causes:"
	assert_contains "$output" "   - Without a unique id, a new deployment overwrites the previous one and rollback is lost"
	assert_contains "$output" "🔧 How to fix:"
	assert_contains "$output" "   • Add {deployment_id} to the pattern"
}

@test "np_naming_validate_pattern: rejects unknown placeholders" {
	run np_naming_validate_pattern "{application}-{team}-{deployment_id}" "deployment_id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Unknown naming placeholder {team}"
	assert_contains "$output" "   • Valid placeholders: {application} {scope} {namespace} {account} {deployment_id} {scope_id} {application_id} {namespace_id}"
}

@test "np_naming_validate_pattern: rejects a pattern starting with a numeric placeholder" {
	run np_naming_validate_pattern "{scope_id}-{application}-{deployment_id}" "deployment_id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{scope_id}-{application}-{deployment_id}' renders a name starting with '1'"
	assert_contains "$output" "   • Kubernetes names must start with a letter; put a slug placeholder first"
}

@test "np_name_render: renders the normal case untrimmed" {
	run np_name_render 46 "{application}-{scope}-{deployment_id}"
	assert_equal "$output" "checkout-api-production-789012"
}

@test "np_name_render: trims the long case within budget" {
	export NP_NAME_APPLICATION="customer-notifications-dispatcher"
	export NP_NAME_SCOPE="production-canary-eu-west"
	run np_name_render 46 "{application}-{scope}-{deployment_id}"
	assert_equal "$output" "customer-notificati-production-canary-e-789012"
	[ "${#output}" -le 46 ]
}

@test "np_name_render: never trims the id" {
	export NP_NAME_APPLICATION="customer-notifications-dispatcher"
	export NP_NAME_SCOPE="production-canary-eu-west"
	run np_name_render 46 "{application}-{scope}-{deployment_id}"
	assert_contains "$output" "789012"
}

@test "np_name_render: two scopes truncating alike still differ" {
	export NP_NAME_SCOPE="production-canary-eu-west"
	run np_name_render 46 "{application}-{scope}-{scope_id}"
	first="$output"
	export NP_NAME_SCOPE="production-canary-us-east"
	export NP_NAME_SCOPE_ID="123457"
	run np_name_render 46 "{application}-{scope}-{scope_id}"
	[ "$first" != "$output" ]
}

@test "np_name_render: aborts naming the placeholder when a flexible value is empty" {
	unset NP_NAME_NAMESPACE
	run np_name_render 46 "{namespace}-{application}-{deployment_id}"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming placeholder {namespace} resolves to an empty value"
	assert_contains "$output" "🔧 How to fix:"
	[[ "$output" != *"segment 1"* ]]
}

@test "np_name_render: does not apply the empty-placeholder check to fixed ids" {
	export NP_NAME_DEPLOYMENT_ID=""
	run np_name_render 46 "{application}-{scope}-{deployment_id}"
	[ "$status" -eq 0 ]
	[[ "$output" != *"resolves to an empty value"* ]]
}
