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
}

@test "np_naming_lookup: returns the object name for a deployment id" {
	kubectl() { [ "$1" = "get" ] && [ "$2" = "hpa" ] && echo "hpa-d-123456-789012"; }
	run np_naming_lookup hpa nullplatform 789012
	assert_equal "$output" "hpa-d-123456-789012"
}

@test "np_naming_lookup: fails and stays silent when nothing matches" {
	kubectl() { [ "$1" = "get" ] && [ "$2" = "hpa" ] && echo ""; }
	run np_naming_lookup hpa nullplatform 789012
	[ "$status" -ne 0 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_blue: finds the main service by its main port" {
	kubectl() {
		case "$2" in
			service) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/svc-ids.json" ;;
			deployment) echo '{"items":[]}' ;;
		esac
	}
	result="$(np_naming_discover_blue nullplatform 789011 8080)"
	run jq -r .service <<< "$result"
	assert_equal "$output" "d-123456-789011"
}

@test "np_naming_discover_blue: finds a per-port GRPC service keyed by port number" {
	kubectl() {
		case "$2" in
			service) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/svc-ids.json" ;;
			deployment) echo '{"items":[]}' ;;
		esac
	}
	result="$(np_naming_discover_blue nullplatform 789011 8080)"
	run jq -r '.ports["9090"]' <<< "$result"
	assert_equal "$output" "d-123456-789011-grpc-9090"
}

@test "np_naming_discover_blue: finds a per-port HTTP service, which carries no port_type label" {
	kubectl() {
		case "$2" in
			service) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/svc-http-port.json" ;;
			deployment) echo '{"items":[]}' ;;
		esac
	}
	result="$(np_naming_discover_blue nullplatform 789011 8080)"
	run jq -r '.ports["9091"]' <<< "$result"
	assert_equal "$output" "d-123456-789011-http-9091"
}

@test "np_naming_discover_blue: returns empty fields when nothing matches" {
	kubectl() { echo '{"items":[]}'; }
	result="$(np_naming_discover_blue nullplatform 789011 8080)"
	run jq -r .service <<< "$result"
	assert_equal "$output" ""
}

@test "np_naming_discover_blue: returns empty fields when there is no blue deployment" {
	kubectl() { echo '{"items":[]}'; }
	result="$(np_naming_discover_blue nullplatform '' 8080)"
	run jq -r .service <<< "$result"
	assert_equal "$output" ""
}

@test "np_naming_discover_blue: finds a blue named by a different strategy" {
	kubectl() {
		case "$2" in
			service) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/svc-qualified.json" ;;
			deployment) echo '{"items":[]}' ;;
		esac
	}
	result="$(np_naming_discover_blue nullplatform 789011 8080)"
	run jq -r .service <<< "$result"
	assert_equal "$output" "checkout-api-production-789011"
}

@test "np_naming_discover_scope: returns the existing ingress name" {
	kubectl() { [ "$2" = "ingress,httproute" ] && cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/ingress-scope.json"; }
	run np_naming_discover_scope nullplatform 123456
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}

@test "np_naming_discover_scope: selects the main ingress by its backend port, regardless of item order" {
	kubectl() { [ "$2" = "ingress,httproute" ] && cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/ingress-scope-additional-port-first.json"; }
	run np_naming_discover_scope nullplatform 123456
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}

@test "np_naming_discover_scope: keeps an HTTPRoute, which has no per-port variant to filter by port" {
	kubectl() { [ "$2" = "ingress,httproute" ] && cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/httproute-scope.json"; }
	run np_naming_discover_scope nullplatform 123456
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}

@test "np_naming_discover_scope: returns not-found when nothing matches" {
	kubectl() { [ "$2" = "ingress,httproute" ] && echo '{"apiVersion":"v1","kind":"List","items":[]}'; }
	run np_naming_discover_scope nullplatform 123456
	[ "$status" -eq 2 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_scope: fails loudly when kubectl fails, instead of computing a fresh name" {
	kubectl() { [ "$2" = "ingress,httproute" ] && return 1; }
	run np_naming_discover_scope nullplatform 123456
	[ "$status" -eq 1 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_dns: returns the existing DNSEndpoint name" {
	kubectl() { [ "$2" = "dnsendpoint" ] && cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/dnsendpoint-scope.json"; }
	run np_naming_discover_dns nullplatform 123456
	assert_equal "$output" "k8s-checkout-api-production-123456-dns"
}

@test "np_naming_discover_dns: returns not-found when nothing matches" {
	kubectl() { [ "$2" = "dnsendpoint" ] && echo '{"apiVersion":"v1","kind":"List","items":[]}'; }
	run np_naming_discover_dns nullplatform 123456
	[ "$status" -eq 2 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_dns: fails loudly when kubectl fails, instead of computing a fresh name" {
	kubectl() { [ "$2" = "dnsendpoint" ] && return 1; }
	run np_naming_discover_dns nullplatform 123456
	[ "$status" -eq 1 ]
	assert_equal "$output" ""
}

@test "qualified: keeps an existing scope ingress name instead of renaming it" {
	export NAMING_STRATEGY=qualified
	kubectl() {
		case "$2" in
			ingress,httproute) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/ingress-scope.json" ;;
			dnsendpoint) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
		esac
	}
	names="$(np_naming_resolve 2>/dev/null)"
	run jq -r .scope_ingress <<< "$names"
	assert_equal "$output" "k-8-s-production-123456-internet-facing"
}

@test "qualified: computes a scope ingress name when none exists" {
	export NAMING_STRATEGY=qualified
	kubectl() { echo '{"apiVersion":"v1","kind":"List","items":[]}'; }
	names="$(np_naming_resolve)"
	run jq -r .scope_ingress <<< "$names"
	assert_equal "$output" "checkout-api-production-123456"
}

@test "qualified: a frozen ingress name does not freeze the deployment name" {
	export NAMING_STRATEGY=qualified
	kubectl() {
		case "$2" in
			ingress,httproute) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/ingress-scope.json" ;;
			dnsendpoint) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
		esac
	}
	names="$(np_naming_resolve 2>/dev/null)"
	run jq -r .deployment <<< "$names"
	assert_equal "$output" "checkout-api-production-789012"
}

@test "qualified: DNS_TYPE route53 never queries the DNSEndpoint" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=route53
	local calls="$BATS_TEST_TMPDIR/kubectl.log"
	: > "$calls"
	kubectl() {
		echo "$*" >> "$calls"
		case "$2" in
			ingress,httproute) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
			*) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
		esac
	}
	run np_naming_resolve
	[ "$status" -eq 0 ]
	run grep -c dnsendpoint "$calls"
	assert_equal "$output" "0"
}

@test "qualified: unset DNS_TYPE never queries the DNSEndpoint" {
	export NAMING_STRATEGY=qualified
	unset DNS_TYPE
	local calls="$BATS_TEST_TMPDIR/kubectl.log"
	: > "$calls"
	kubectl() {
		echo "$*" >> "$calls"
		case "$2" in
			ingress,httproute) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
			*) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
		esac
	}
	run np_naming_resolve
	[ "$status" -eq 0 ]
	run grep -c dnsendpoint "$calls"
	assert_equal "$output" "0"
}

@test "qualified: keeps an existing DNSEndpoint name instead of renaming it" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	kubectl() {
		case "$2" in
			ingress,httproute) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
			dnsendpoint) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/dnsendpoint-scope.json" ;;
		esac
	}
	names="$(np_naming_resolve 2>/dev/null)"
	run jq -r .scope_dns <<< "$names"
	assert_equal "$output" "k8s-checkout-api-production-123456-dns"
}

@test "qualified: computes a scope dns name when none exists" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	kubectl() { echo '{"apiVersion":"v1","kind":"List","items":[]}'; }
	names="$(np_naming_resolve)"
	run jq -r .scope_dns <<< "$names"
	assert_equal "$output" "checkout-api-production-123456-dns"
}

@test "qualified: keeping an existing name is logged" {
	export NAMING_STRATEGY=qualified
	kubectl() {
		case "$2" in
			ingress,httproute) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/ingress-scope.json" ;;
			dnsendpoint) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
		esac
	}
	run np_naming_resolve
	assert_contains "$output" "✅ Keeping the existing scope object name 'k-8-s-production-123456-internet-facing'"
}

@test "qualified: keeping an existing DNS name is logged" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	kubectl() {
		case "$2" in
			ingress,httproute) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
			dnsendpoint) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/dnsendpoint-scope.json" ;;
		esac
	}
	run np_naming_resolve
	assert_contains "$output" "✅ Keeping the existing scope DNS object name 'k8s-checkout-api-production-123456-dns'"
}

@test "qualified: the resolved JSON on stdout stays valid when an existing name is kept" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	kubectl() {
		case "$2" in
			ingress,httproute) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/ingress-scope.json" ;;
			dnsendpoint) cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/dnsendpoint-scope.json" ;;
		esac
	}
	names="$(np_naming_resolve 2>/dev/null)"
	run jq -e . <<< "$names"
	[ "$status" -eq 0 ]
}

@test "qualified: a failed ingress/httproute lookup fails resolve instead of computing a fresh name" {
	export NAMING_STRATEGY=qualified
	kubectl() { [ "$2" = "ingress,httproute" ] && return 1; }
	run np_naming_resolve
	[ "$status" -eq 1 ]
	assert_contains "$output" "❌ Could not check the cluster for the scope's existing Kubernetes object name"
	assert_contains "$output" "💡 Possible causes:"
	assert_contains "$output" "🔧 How to fix:"
}

@test "qualified: a failed dnsendpoint lookup fails resolve instead of computing a fresh name" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	kubectl() {
		case "$2" in
			ingress,httproute) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
			dnsendpoint) return 1 ;;
		esac
	}
	run np_naming_resolve
	[ "$status" -eq 1 ]
	assert_contains "$output" "❌ Could not check the cluster for the scope's existing DNSEndpoint name"
	assert_contains "$output" "💡 Possible causes:"
	assert_contains "$output" "🔧 How to fix:"
}
