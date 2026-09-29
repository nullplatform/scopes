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

@test "np_naming_validate_pattern: accepts a pattern missing its discriminant by appending it" {
	run np_naming_validate_pattern "{.application.slug}-{.scope.slug}" "deployment.id"
	[ "$status" -eq 0 ]
}

@test "np_name_render: appends the deployment discriminant when the pattern omits it" {
	result="$(np_name_render 46 "{.application.slug}-{.scope.slug}" "deployment.id" 2>/dev/null)"
	assert_equal "$result" "checkout-api-production-789012"
}

@test "np_name_render: appends the scope discriminant when the pattern omits it" {
	result="$(np_name_render 52 "{.application.slug}-{.scope.slug}" "scope.id" 2>/dev/null)"
	assert_equal "$result" "checkout-api-production-123456"
}

@test "np_name_render: reports the appended discriminant on stderr" {
	warn_line="$(np_name_render 46 "{.application.slug}-{.scope.slug}" "deployment.id" 2>&1 1>/dev/null)"
	assert_equal "$warn_line" "⚠️  Naming pattern does not contain {.deployment.id}; appended it, effective pattern is '{.application.slug}-{.scope.slug}-{.deployment.id}'"
}

@test "np_name_render: leaves a pattern that already carries its discriminant unchanged" {
	result="$(np_name_render 46 "{.application.slug}-{.deployment.id}-{.scope.slug}" "deployment.id" 2>/dev/null)"
	assert_equal "$result" "checkout-api-789012-production"
}

@test "np_name_render: emits no warning when the discriminant is already present" {
	run np_name_render 46 "{.application.slug}-{.deployment.id}-{.scope.slug}" "deployment.id"
	[ "$status" -eq 0 ]
	case "$output" in
		*"appended it"*) false ;;
		*) true ;;
	esac
}

@test "np_name_render: the appended discriminant survives trimming under budget" {
	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long.json")"
	result="$(np_name_render 46 "{.application.slug}-{.scope.slug}" "deployment.id" 2>/dev/null)"
	assert_equal "$result" "customer-notificati-production-canary-e-789012"
	[ "${#result}" -le 46 ]
	assert_contains "$result" "789012"
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

@test "custom: falls back to the qualified scope pattern when only the deployment pattern is set" {
	export NAMING_STRATEGY=custom
	export NAMING_DEPLOYMENT_PATTERN="{.namespace.slug}-{.application.slug}-{.deployment.id}"
	kubectl() { echo ""; }
	names="$(np_naming_resolve)"
	run jq -r '.deployment, .scope_ingress' <<< "$names"
	assert_equal "$(echo "$output" | sed -n 1p)" "payments-checkout-api-789012"
	assert_equal "$(echo "$output" | sed -n 2p)" "checkout-api-production-123456"
}

@test "custom: falls back to the qualified deployment pattern when only the scope pattern is set" {
	export NAMING_STRATEGY=custom
	export NAMING_SCOPE_PATTERN="{.namespace.slug}-{.scope.slug}-{.scope.id}"
	kubectl() { echo ""; }
	names="$(np_naming_resolve)"
	run jq -r '.deployment, .scope_ingress' <<< "$names"
	assert_equal "$(echo "$output" | sed -n 1p)" "checkout-api-production-789012"
	assert_equal "$(echo "$output" | sed -n 2p)" "payments-production-123456"
}

@test "custom: honours a deployment pattern from the provider" {
	export NAMING_STRATEGY=custom
	export CONTEXT="$(echo "$CONTEXT" | jq '.providers["scope-configurations"].naming.deployment_pattern = "{.namespace.slug}-{.application.slug}-{.deployment.id}"')"
	names="$(np_naming_resolve)"
	run jq -r .deployment <<< "$names"
	assert_equal "$output" "payments-checkout-api-789012"
}

@test "custom: a pattern without the discriminant renders instead of aborting" {
	export NAMING_STRATEGY=custom
	export CONTEXT="$(echo "$CONTEXT" | jq '.providers["scope-configurations"].naming.deployment_pattern = "{.application.slug}-{.scope.slug}"')"
	names="$(np_naming_resolve 2>/dev/null)"
	run jq -r .deployment <<< "$names"
	assert_equal "$output" "checkout-api-production-789012"
}

@test "custom: appending the discriminant is reported on stderr while stdout stays valid JSON" {
	export NAMING_STRATEGY=custom
	export CONTEXT="$(echo "$CONTEXT" | jq '.providers["scope-configurations"].naming.deployment_pattern = "{.application.slug}-{.scope.slug}"')"
	kubectl() { echo ""; }
	local err_file
	err_file="$(mktemp)"
	names="$(np_naming_resolve 2>"$err_file")"
	assert_equal "$(cat "$err_file")" "⚠️  Naming pattern does not contain {.deployment.id}; appended it, effective pattern is '{.application.slug}-{.scope.slug}-{.deployment.id}'"
	run jq empty <<< "$names"
	[ "$status" -eq 0 ]
	rm -f "$err_file"
}
