#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log
	source "$PROJECT_ROOT/k8s/naming/resolve_names"
}

@test "np_name_sanitize: lowercases and replaces invalid characters" {
	run np_name_sanitize "Checkout_API v2"
	assert_equal "$output" "checkout-api-v2"
}

@test "np_name_sanitize: collapses repeats and strips edge hyphens" {
	run np_name_sanitize "--foo___bar--"
	assert_equal "$output" "foo-bar"
}

@test "np_name_cap: returns the largest cap that fits" {
	run np_name_cap 38 33 25
	assert_equal "$output" "19"
}

@test "np_name_cap: returns a cap above every length when they all fit" {
	run np_name_cap 38 3 25
	[ "$output" -ge 25 ]
}

@test "np_trim_name: returns segments untouched when they fit" {
	run np_trim_name 46 8 "checkout-api" "production"
	assert_equal "$output" "checkout-api-production"
}

@test "np_trim_name: water-fills two long segments" {
	run np_trim_name 46 8 "customer-notifications-dispatcher" "production-canary-eu-west"
	assert_equal "$output" "customer-notificati-production-canary-e"
}

@test "np_trim_name: spares the short segment when only one is long" {
	run np_trim_name 46 8 "api" "production-canary-eu-west"
	assert_equal "$output" "api-production-canary-eu-west"
}

@test "np_trim_name: never leaves a doubled or trailing hyphen" {
	run np_trim_name 20 8 "checkout-api" "production"
	assert_equal "$output" "checko-produc"
}

@test "np_trim_name: fails when the overhead alone exhausts the budget" {
	run np_trim_name 8 8 "checkout-api" "production"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Name budget 8 is too small: separators and ids already need 8 characters"
}

@test "np_trim_name: fails when the cap falls below three characters" {
	run np_trim_name 12 8 "customer-notifications-dispatcher" "production-canary-eu-west"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Name budget 12 leaves 4 characters for 2 slug segments, under the 3-character minimum"
}

@test "np_trim_name: fails when the first segment is empty" {
	run np_trim_name 46 8 "" "production"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Slug segment 1 is empty after sanitising; a Kubernetes name cannot contain an empty component"
}

@test "np_trim_name: fails when the second segment is empty" {
	run np_trim_name 46 8 "production" ""
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Slug segment 2 is empty after sanitising; a Kubernetes name cannot contain an empty component"
}

@test "np_trim_name: fails when a segment sanitises to empty" {
	run np_trim_name 46 8 "----" "production"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Slug segment 1 is empty after sanitising; a Kubernetes name cannot contain an empty component"
}

@test "np_trim_name: never returns a leading, trailing or doubled hyphen" {
	run np_trim_name 46 8 "checkout-api" "production"
	[[ "$output" != -* ]]
	[[ "$output" != *- ]]
	[[ "$output" != *--* ]]

	run np_trim_name 46 8 "customer-notifications-dispatcher" "production-canary-eu-west"
	[[ "$output" != -* ]]
	[[ "$output" != *- ]]
	[[ "$output" != *--* ]]

	run np_trim_name 20 8 "checkout-api" "production"
	[[ "$output" != -* ]]
	[[ "$output" != *- ]]
	[[ "$output" != *--* ]]
}

@test "np_trim_segments: emits one line per segment when they fit" {
	run np_trim_segments 46 8 "checkout-api" "production"
	[ "${#lines[@]}" -eq 2 ]
	assert_equal "${lines[0]}" "checkout-api"
	assert_equal "${lines[1]}" "production"
}

@test "np_trim_segments: emits one line per segment when trimmed" {
	run np_trim_segments 46 8 "customer-notifications-dispatcher" "production-canary-eu-west"
	[ "${#lines[@]}" -eq 2 ]
	assert_equal "${lines[0]}" "customer-notificati"
	assert_equal "${lines[1]}" "production-canary-e"
}

@test "np_trim_segments: fails when a segment is empty after sanitising" {
	run np_trim_segments 46 8 "" "production"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Slug segment 1 is empty after sanitising; a Kubernetes name cannot contain an empty component"
}

@test "np_trim_segments: fails when the cap falls below three characters" {
	run np_trim_segments 12 8 "customer-notifications-dispatcher" "production-canary-eu-west"
	[ "$status" -ne 0 ]
	assert_contains "$output" "❌ Name budget 12 leaves 4 characters for 2 slug segments, under the 3-character minimum"
}
