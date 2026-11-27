#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log
	source "$PROJECT_ROOT/k8s/utils/get_config_value"
	source "$PROJECT_ROOT/k8s/naming/resolve_names"

	export CONTEXT="$(jq '. + {service_to_service: {enabled: true, name_pattern: "{.application.slug}-{.scope.slug}"}}' \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal.json")"
	unset NAMING_STRATEGY
	unset NAMING_MAX_LENGTH
	export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
}

@test "stable_service: absent when service-to-service is disabled" {
	export CONTEXT="$(jq 'del(.service_to_service)' <<< "$CONTEXT")"
	kubectl() { echo "$*" >> "$KUBECTL_LOG"; echo ""; }
	names="$(np_naming_resolve)"
	assert_equal "$(jq -r 'has("stable_service")' <<< "$names")" "false"
	[[ "$(cat "$KUBECTL_LOG")" != *"stable-service"* ]] || false
}

@test "stable_service: renders the pattern without appending an id" {
	kubectl() { echo ""; }
	names="$(np_naming_resolve)"
	assert_equal "$(jq -r .stable_service <<< "$names")" "checkout-api-production"
}

@test "stable_service: does not change any other name" {
	kubectl() { echo ""; }
	enabled="$(np_naming_resolve | jq -S 'del(.stable_service)')"
	export CONTEXT="$(jq 'del(.service_to_service)' <<< "$CONTEXT")"
	disabled="$(np_naming_resolve | jq -S .)"
	assert_equal "$enabled" "$disabled"
}

@test "stable_service: the same name under every strategy" {
	kubectl() { echo ""; }
	for strategy in ids qualified custom; do
		export NAMING_STRATEGY=$strategy
		assert_equal "$(np_naming_resolve | jq -r .stable_service)" "checkout-api-production"
	done
}

@test "stable_service: honours a custom name_pattern" {
	export CONTEXT="$(jq '.service_to_service.name_pattern = "{.namespace.slug}-{.application.slug}"' <<< "$CONTEXT")"
	kubectl() { echo ""; }
	assert_equal "$(np_naming_resolve | jq -r .stable_service)" "payments-checkout-api"
}

@test "stable_service: trims long slugs to the 63-character Service name limit" {
	export CONTEXT="$(jq '.application.slug = ("a" * 50) | .scope.slug = ("b" * 50)' <<< "$CONTEXT")"
	kubectl() { echo ""; }
	name="$(np_naming_resolve | jq -r .stable_service)"
	[ "${#name}" -le 63 ]
	assert_equal "$name" "$(printf 'a%.0s' {1..31})-$(printf 'b%.0s' {1..31})"
}

@test "stable_service: keeps the existing name found by its labels instead of renaming it" {
	export CONTEXT="$(jq '.service_to_service.name_pattern = "{.namespace.slug}-{.scope.slug}"' <<< "$CONTEXT")"
	kubectl() {
		echo "$*" >> "$KUBECTL_LOG"
		[ "$2" = "service" ] && echo "checkout-api-production"
		return 0
	}
	names="$(np_naming_resolve 2>/dev/null)"
	assert_equal "$(jq -r .stable_service <<< "$names")" "checkout-api-production"
	assert_contains "$(cat "$KUBECTL_LOG")" "get service -n nullplatform -l nullplatform.io/stable-service=true,scope_id=123456"
}

@test "stable_service: fails loudly when the lookup fails, instead of computing a fresh name" {
	kubectl() {
		[ "$2" = "service" ] && { echo "Error from server (Forbidden): ..."; return 1; }
		echo ""
	}
	run np_naming_resolve
	[ "$status" -eq 1 ]
	assert_contains "$output" "❌ Could not check the cluster for the scope's existing stable service name"
}

@test "stable_service: an internal HTTPRoute is never taken for the scope's main HTTPRoute" {
	kubectl() {
		case "$2" in
			ingress) echo "" ;;
			httproute) echo "checkout-api-production-http-8080 checkout-api-production-http-8081 k-8-s-production-123456-internet-facing" ;;
		esac
	}
	run np_naming_discover_scope nullplatform 123456
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}
