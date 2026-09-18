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

	export NP_NAME_SCOPE="production"
	export NP_NAME_APPLICATION="checkout-api"

	GOLDEN_DIR="$PROJECT_ROOT/k8s/naming/tests/goldens/normal"
}

golden_name() {
	yq -N "select(document_index == $2) | .metadata.name" "$GOLDEN_DIR/$1"
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

@test "np_naming_object_exists: found returns 0" {
	kubectl() { [ "$2" = "ingress" ] && [ "$3" = "my-ingress" ] && echo "ingress.networking.k8s.io/my-ingress"; }
	run np_naming_object_exists ingress nullplatform my-ingress
	[ "$status" -eq 0 ]
}

@test "np_naming_object_exists: --ignore-not-found empty output is not-found" {
	kubectl() { [ "$2" = "ingress" ] && echo ""; }
	run np_naming_object_exists ingress nullplatform my-ingress
	[ "$status" -eq 2 ]
}

@test "np_naming_object_exists: an unregistered resource type is not-found, not a failure" {
	kubectl() { echo "error: the server doesn't have a resource type \"$2\""; return 1; }
	run np_naming_object_exists httproute nullplatform my-ingress
	[ "$status" -eq 2 ]
}

@test "np_naming_object_exists: any other failure is fatal" {
	kubectl() { echo "Error from server (Forbidden): ..."; return 1; }
	run np_naming_object_exists ingress nullplatform my-ingress
	[ "$status" -eq 1 ]
}

@test "np_naming_discover_scope: keeps the legacy name when the live Ingress is blue-green shaped" {
	local name; name="$(golden_name k8s-blue-green-ingress.yaml 0)"
	kubectl() { [ "$2" = "ingress" ] && [ "$3" = "$name" ] && echo "ingress.networking.k8s.io/$name"; }
	run np_naming_discover_scope nullplatform 123456
	assert_equal "$output" "$name"
}

@test "np_naming_discover_scope: keeps the legacy name when the live Ingress is initial shaped" {
	local name; name="$(golden_name k8s-initial-ingress.yaml 0)"
	kubectl() { [ "$2" = "ingress" ] && [ "$3" = "$name" ] && echo "ingress.networking.k8s.io/$name"; }
	run np_naming_discover_scope nullplatform 123456
	assert_equal "$output" "$name"
}

@test "np_naming_discover_scope: a per-port Ingress existing does not make it the main one, blue-green shape" {
	local port_name; port_name="$(golden_name k8s-blue-green-ingress.yaml 1)"
	kubectl() {
		if [ "$2" = "ingress" ] && [ "$3" = "$port_name" ]; then
			echo "ingress.networking.k8s.io/$port_name"
		else
			echo ""
		fi
	}
	run np_naming_discover_scope nullplatform 123456
	[ "$status" -eq 2 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_scope: a per-port Ingress existing does not make it the main one, initial shape" {
	local port_name; port_name="$(golden_name k8s-initial-ingress.yaml 1)"
	kubectl() {
		if [ "$2" = "ingress" ] && [ "$3" = "$port_name" ]; then
			echo "ingress.networking.k8s.io/$port_name"
		else
			echo ""
		fi
	}
	run np_naming_discover_scope nullplatform 123456
	[ "$status" -eq 2 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_scope: falls through to HTTPRoute when the Ingress does not exist" {
	local name; name="$(golden_name k8s-istio-initial-httproute.yaml 0)"
	kubectl() {
		case "$2" in
			ingress) echo "" ;;
			httproute) [ "$3" = "$name" ] && echo "httproute.gateway.networking.k8s.io/$name" ;;
		esac
	}
	run np_naming_discover_scope nullplatform 123456
	assert_equal "$output" "$name"
}

@test "np_naming_discover_scope: returns not-found when neither Ingress nor HTTPRoute exist" {
	kubectl() { echo ""; }
	run np_naming_discover_scope nullplatform 123456
	[ "$status" -eq 2 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_scope: fails loudly when the Ingress lookup fails, instead of computing a fresh name" {
	kubectl() { [ "$2" = "ingress" ] && { echo "Error from server (Forbidden): ..."; return 1; }; }
	run np_naming_discover_scope nullplatform 123456
	[ "$status" -eq 1 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_scope: fails loudly when the HTTPRoute lookup fails, instead of computing a fresh name" {
	kubectl() {
		case "$2" in
			ingress) echo "" ;;
			httproute) echo "Error from server (Forbidden): ..."; return 1 ;;
		esac
	}
	run np_naming_discover_scope nullplatform 123456
	[ "$status" -eq 1 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_scope: an unregistered HTTPRoute type is not-found, not a failure" {
	kubectl() {
		case "$2" in
			ingress) echo "" ;;
			httproute) echo "error: the server doesn't have a resource type \"httproute\""; return 1 ;;
		esac
	}
	run np_naming_discover_scope nullplatform 123456
	[ "$status" -eq 2 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_dns: keeps the legacy DNSEndpoint name from the golden" {
	local name; name="$(golden_name k8s-dns-endpoint.yaml 0)"
	kubectl() { [ "$2" = "dnsendpoint" ] && [ "$3" = "$name" ] && echo "dnsendpoint.externaldns.k8s.io/$name"; }
	run np_naming_discover_dns nullplatform 123456
	assert_equal "$output" "$name"
}

@test "np_naming_discover_dns: returns not-found when nothing matches" {
	kubectl() { echo ""; }
	run np_naming_discover_dns nullplatform 123456
	[ "$status" -eq 2 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_dns: fails loudly when kubectl fails, instead of computing a fresh name" {
	kubectl() { echo "Error from server (Forbidden): ..."; return 1; }
	run np_naming_discover_dns nullplatform 123456
	[ "$status" -eq 1 ]
	assert_equal "$output" ""
}

@test "np_naming_discover_dns: an unregistered DNSEndpoint type is not-found, not a failure" {
	kubectl() { echo "error: the server doesn't have a resource type \"dnsendpoint\""; return 1; }
	run np_naming_discover_dns nullplatform 123456
	[ "$status" -eq 2 ]
	assert_equal "$output" ""
}

@test "qualified: keeps an existing scope ingress name instead of renaming it" {
	export NAMING_STRATEGY=qualified
	local name; name="$(golden_name k8s-blue-green-ingress.yaml 0)"
	kubectl() { [ "$2" = "ingress" ] && [ "$3" = "$name" ] && echo "ingress.networking.k8s.io/$name"; }
	names="$(np_naming_resolve 2>/dev/null)"
	run jq -r .scope_ingress <<< "$names"
	assert_equal "$output" "$name"
}

@test "qualified: computes a scope ingress name when none exists" {
	export NAMING_STRATEGY=qualified
	kubectl() { echo ""; }
	names="$(np_naming_resolve)"
	run jq -r .scope_ingress <<< "$names"
	assert_equal "$output" "checkout-api-production-123456"
}

@test "qualified: a frozen ingress name does not freeze the deployment name" {
	export NAMING_STRATEGY=qualified
	local name; name="$(golden_name k8s-blue-green-ingress.yaml 0)"
	kubectl() { [ "$2" = "ingress" ] && [ "$3" = "$name" ] && echo "ingress.networking.k8s.io/$name"; }
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
		echo ""
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
		echo ""
	}
	run np_naming_resolve
	[ "$status" -eq 0 ]
	run grep -c dnsendpoint "$calls"
	assert_equal "$output" "0"
}

@test "qualified: keeps an existing DNSEndpoint name instead of renaming it" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	local dns_name; dns_name="$(golden_name k8s-dns-endpoint.yaml 0)"
	kubectl() {
		case "$2" in
			ingress) echo "" ;;
			dnsendpoint) [ "$3" = "$dns_name" ] && echo "dnsendpoint.externaldns.k8s.io/$dns_name" ;;
		esac
	}
	names="$(np_naming_resolve 2>/dev/null)"
	run jq -r .scope_dns <<< "$names"
	assert_equal "$output" "$dns_name"
}

@test "qualified: computes a scope dns name when none exists" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	kubectl() { echo ""; }
	names="$(np_naming_resolve)"
	run jq -r .scope_dns <<< "$names"
	assert_equal "$output" "checkout-api-production-123456-dns"
}

@test "qualified: keeping an existing name is logged" {
	export NAMING_STRATEGY=qualified
	local name; name="$(golden_name k8s-initial-ingress.yaml 0)"
	kubectl() { [ "$2" = "ingress" ] && [ "$3" = "$name" ] && echo "ingress.networking.k8s.io/$name"; }
	run np_naming_resolve
	assert_contains "$output" "✅ Keeping the existing scope object name '$name'"
}

@test "qualified: keeping an existing DNS name is logged" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	local dns_name; dns_name="$(golden_name k8s-dns-endpoint.yaml 0)"
	kubectl() {
		case "$2" in
			ingress) echo "" ;;
			dnsendpoint) [ "$3" = "$dns_name" ] && echo "dnsendpoint.externaldns.k8s.io/$dns_name" ;;
		esac
	}
	run np_naming_resolve
	assert_contains "$output" "✅ Keeping the existing scope DNS object name '$dns_name'"
}

@test "qualified: the resolved JSON on stdout stays valid when an existing name is kept" {
	export NAMING_STRATEGY=qualified
	export DNS_TYPE=external_dns
	local name dns_name
	name="$(golden_name k8s-initial-ingress.yaml 0)"
	dns_name="$(golden_name k8s-dns-endpoint.yaml 0)"
	kubectl() {
		case "$2" in
			ingress) [ "$3" = "$name" ] && echo "ingress.networking.k8s.io/$name" ;;
			dnsendpoint) [ "$3" = "$dns_name" ] && echo "dnsendpoint.externaldns.k8s.io/$dns_name" ;;
		esac
	}
	names="$(np_naming_resolve 2>/dev/null)"
	run jq -e . <<< "$names"
	[ "$status" -eq 0 ]
}

@test "qualified: a failed ingress lookup fails resolve instead of computing a fresh name" {
	export NAMING_STRATEGY=qualified
	kubectl() { [ "$2" = "ingress" ] && { echo "Error from server (Forbidden): ..."; return 1; }; }
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
			ingress) echo "" ;;
			dnsendpoint) echo "Error from server (Forbidden): ..."; return 1 ;;
		esac
	}
	run np_naming_resolve
	[ "$status" -eq 1 ]
	assert_contains "$output" "❌ Could not check the cluster for the scope's existing DNSEndpoint name"
	assert_contains "$output" "💡 Possible causes:"
	assert_contains "$output" "🔧 How to fix:"
}
