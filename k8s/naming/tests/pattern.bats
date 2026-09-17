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
		np_naming_emit np_naming_roles_patterned np_naming_lookup np_naming_discover_blue
	export NP_NAME_PLACEHOLDERS NP_NAME_FIXED_PLACEHOLDERS \
		NP_NAMING_DEPLOYMENT_PATTERN_DEFAULT NP_NAMING_SCOPE_PATTERN_DEFAULT NP_NAMING_SCOPE_BUDGET

	export NP_NAME_APPLICATION="checkout-api"
	export NP_NAME_SCOPE="production"
	export NP_NAME_NAMESPACE="payments"
	export NP_NAME_ACCOUNT="acme"
	export NP_NAME_DEPLOYMENT_ID="789012"
	export NP_NAME_SCOPE_ID="123456"
	export NP_NAME_APPLICATION_ID="111"
	export NP_NAME_NAMESPACE_ID="11"

	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal.json")"
	unset NAMING_STRATEGY
	unset NAMING_MAX_LENGTH
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

@test "np_naming_validate_pattern: rejects a separator that is not a single hyphen" {
	run np_naming_validate_pattern "{application}.{scope}-{deployment_id}" "deployment_id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{application}.{scope}-{deployment_id}' uses '.' between placeholders"
	assert_contains "$output" "   • Separate placeholders with a single hyphen"
}

@test "np_naming_validate_pattern: rejects literals that alone exceed the budget" {
	run np_naming_validate_pattern "prefix-that-is-far-too-long-to-ever-possibly-fit-{application}-{deployment_id}" "deployment_id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "leaving nothing for the slugs"
}

@test "np_name_render: three hyphenated placeholders return every segment intact" {
	export NP_NAME_SCOPE="production-canary"
	export NP_NAME_NAMESPACE="multi-word-value"
	run np_name_render 60 "{application}-{scope}-{namespace}"
	assert_equal "$output" "checkout-api-production-canary-multi-word-value"
}

@test "custom: honours a deployment pattern from the provider" {
	export NAMING_STRATEGY=custom
	kubectl() { echo ""; }
	export -f kubectl
	export CONTEXT="$(echo "$CONTEXT" | jq '.providers["scope-configurations"].naming.deployment_pattern = "{namespace}-{application}-{deployment_id}"')"
	run bash -c "np_naming_resolve | jq -r .deployment"
	assert_equal "$output" "payments-checkout-api-789012"
}

@test "custom: a pattern without the discriminant aborts" {
	export NAMING_STRATEGY=custom
	export CONTEXT="$(echo "$CONTEXT" | jq '.providers["scope-configurations"].naming.deployment_pattern = "{application}-{scope}"')"
	run np_naming_resolve
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{application}-{scope}' does not contain {deployment_id}"
}
