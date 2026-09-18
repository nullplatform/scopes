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

@test "np_naming_validate_pattern: accepts a pattern carrying its discriminant" {
	run np_naming_validate_pattern "{.application.slug}-{.scope.slug}-{.deployment.id}" "deployment.id"
	[ "$status" -eq 0 ]
}

@test "np_naming_validate_pattern: rejects a pattern without its discriminant" {
	run np_naming_validate_pattern "{.application.slug}-{.scope.slug}" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{.application.slug}-{.scope.slug}' does not contain {.deployment.id}"
	assert_contains "$output" "💡 Possible causes:"
	assert_contains "$output" "   - Without a unique id, a new deployment overwrites the previous one and rollback is lost"
	assert_contains "$output" "🔧 How to fix:"
	assert_contains "$output" "   • Add {.deployment.id} to the pattern"
}

@test "np_naming_validate_pattern: rejects a pipe in the path" {
	run np_naming_validate_pattern "{.application.slug}-{.foo | @sh}-{.deployment.id}" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{.application.slug}-{.foo | @sh}-{.deployment.id}' has an unsafe path {.foo | @sh}"
	assert_contains "$output" "🔧 How to fix:"
}

@test "np_naming_validate_pattern: rejects a variable binding in the path" {
	run np_naming_validate_pattern '{.application.slug}-{.foo as $x | $x}-{.deployment.id}' "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" 'has an unsafe path {.foo as $x | $x}'
}

@test "np_naming_validate_pattern: rejects a stray quote in the path" {
	run np_naming_validate_pattern '{.application.slug}-{."literal"}-{.deployment.id}' "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" 'has an unsafe path {."literal"}'
}

@test "np_naming_validate_pattern: rejects a path that resolves to nothing" {
	run np_naming_validate_pattern "{.application.slug}-{.scope.missing_field}-{.deployment.id}" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming path {.scope.missing_field} resolves to an empty value"
	assert_contains "$output" "🔧 How to fix:"
}

@test "np_naming_validate_pattern: rejects a pattern starting with a numeric placeholder" {
	run np_naming_validate_pattern "{.scope.id}-{.application.slug}-{.deployment.id}" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{.scope.id}-{.application.slug}-{.deployment.id}' renders a name starting with '1'"
	assert_contains "$output" "   • Kubernetes names must start with a letter; put a slug placeholder first"
}

@test "np_name_render: renders the normal case untrimmed" {
	run np_name_render 46 "{.application.slug}-{.scope.slug}-{.deployment.id}"
	assert_equal "$output" "checkout-api-production-789012"
}

@test "np_name_render: reaches a capabilities field the old allowlist could not express" {
	run np_name_render 46 "{.application.slug}-{.scope.capabilities.main_http_port}-{.deployment.id}"
	assert_equal "$output" "checkout-api-8080-789012"
}

@test "np_name_render: trims the long case within budget" {
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json")"
	run np_name_render 46 "{.application.slug}-{.scope.slug}-{.deployment.id}"
	assert_equal "$output" "customer-notificati-production-canary-e-789012"
	[ "${#output}" -le 46 ]
}

@test "np_name_render: never trims the id" {
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json")"
	run np_name_render 46 "{.application.slug}-{.scope.slug}-{.deployment.id}"
	assert_contains "$output" "789012"
}

@test "np_name_render: a numeric path is never trimmed while a slug path shrinks" {
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json")"
	run np_name_render 30 "{.application.slug}-{.scope.id}"
	assert_equal "$output" "customer-notifications-123456"
	[ "${#output}" -le 30 ]
}

@test "np_name_render: two scopes truncating alike still differ" {
	export CONTEXT="$(echo "$CONTEXT" | jq '.scope.slug = "production-canary-eu-west"')"
	run np_name_render 46 "{.application.slug}-{.scope.slug}-{.scope.id}"
	first="$output"
	export CONTEXT="$(echo "$CONTEXT" | jq '.scope.slug = "production-canary-us-east" | .scope.id = 123457')"
	run np_name_render 46 "{.application.slug}-{.scope.slug}-{.scope.id}"
	[ "$first" != "$output" ]
}

@test "np_name_render: aborts naming the path when a flexible value is empty" {
	export CONTEXT="$(echo "$CONTEXT" | jq 'del(.namespace)')"
	run np_name_render 46 "{.namespace.slug}-{.application.slug}-{.deployment.id}"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming path {.namespace.slug} resolves to an empty value"
	assert_contains "$output" "🔧 How to fix:"
}

@test "np_naming_validate_pattern: rejects a separator that is not a single hyphen" {
	run np_naming_validate_pattern "{.application.slug}.{.scope.slug}-{.deployment.id}" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{.application.slug}.{.scope.slug}-{.deployment.id}' uses '.' between placeholders"
	assert_contains "$output" "   • Separate placeholders with a single hyphen"
}

@test "np_naming_validate_pattern: rejects literals that alone exceed the budget" {
	run np_naming_validate_pattern "prefix-that-is-far-too-long-to-ever-possibly-fit-{.application.slug}-{.deployment.id}" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "leaving nothing for the slugs"
}

@test "np_name_render: three hyphenated placeholders return every segment intact" {
	export CONTEXT="$(echo "$CONTEXT" | jq '.scope.slug = "production-canary" | .namespace.slug = "multi-word-value"')"
	run np_name_render 60 "{.application.slug}-{.scope.slug}-{.namespace.slug}"
	assert_equal "$output" "checkout-api-production-canary-multi-word-value"
}

@test "np_naming_validate_pattern: still rejects a bad separator when a leading literal is present" {
	run np_naming_validate_pattern "fede-{.application.slug}.{.scope.slug}-{.deployment.id}" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "uses '.' between placeholders"
}

@test "np_naming_validate_pattern: accepts a leading literal of lowercase letters, digits and hyphens" {
	run np_naming_validate_pattern "fede2-{.application.slug}-{.deployment.id}" "deployment.id"
	[ "$status" -eq 0 ]
}

@test "np_naming_validate_pattern: rejects a leading literal with characters Kubernetes does not allow" {
	run np_naming_validate_pattern "Fede_{.application.slug}-{.deployment.id}" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern 'Fede_{.application.slug}-{.deployment.id}' has an invalid leading literal 'Fede_'"
	assert_contains "$output" "🔧 How to fix:"
}

@test "np_naming_validate_pattern: accepts a trailing literal" {
	run np_naming_validate_pattern "{.application.slug}-{.deployment.id}-suffix" "deployment.id"
	[ "$status" -eq 0 ]
}

@test "np_naming_validate_pattern: rejects a trailing literal with characters Kubernetes does not allow" {
	run np_naming_validate_pattern "{.application.slug}-{.deployment.id}-Suffix!" "deployment.id"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{.application.slug}-{.deployment.id}-Suffix!' has an invalid trailing literal '-Suffix!'"
	assert_contains "$output" "🔧 How to fix:"
}

@test "np_name_render: keeps a leading literal prefix intact" {
	run np_name_render 46 "fede-{.application.slug}-{.deployment.id}"
	assert_equal "$output" "fede-checkout-api-789012"
}

@test "np_name_render: emits a trailing literal after the last placeholder" {
	run np_name_render 46 "{.application.slug}-{.deployment.id}-suffix"
	assert_equal "$output" "checkout-api-789012-suffix"
}

@test "np_name_render: emits both a leading and a trailing literal" {
	run np_name_render 46 "fede-{.application.slug}-{.deployment.id}-suffix"
	assert_equal "$output" "fede-checkout-api-789012-suffix"
}

@test "np_name_render: a leading literal counts against the budget while the id stays untrimmed" {
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json")"
	run np_name_render 46 "fede-{.application.slug}-{.scope.slug}-{.deployment.id}"
	assert_equal "$output" "fede-customer-notific-production-canar-789012"
	[ "${#output}" -le 46 ]
	assert_contains "$output" "789012"
}

@test "np_name_render: qualified default patterns render unchanged with no leading or trailing literal" {
	run np_name_render 46 "$NP_NAMING_DEPLOYMENT_PATTERN_DEFAULT"
	assert_equal "$output" "checkout-api-production-789012"
}

@test "custom: honours a deployment pattern from the provider" {
	export NAMING_STRATEGY=custom
	export CONTEXT="$(echo "$CONTEXT" | jq '.providers["scope-configurations"].naming.deployment_pattern = "{.namespace.slug}-{.application.slug}-{.deployment.id}"')"
	names="$(np_naming_resolve)"
	run jq -r .deployment <<< "$names"
	assert_equal "$output" "payments-checkout-api-789012"
}

@test "custom: a pattern without the discriminant aborts" {
	export NAMING_STRATEGY=custom
	export CONTEXT="$(echo "$CONTEXT" | jq '.providers["scope-configurations"].naming.deployment_pattern = "{.application.slug}-{.scope.slug}"')"
	run np_naming_resolve
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Naming pattern '{.application.slug}-{.scope.slug}' does not contain {.deployment.id}"
}
