#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log
	source "$PROJECT_ROOT/k8s/utils/get_config_value"

	export SCRIPT="$PROJECT_ROOT/k8s/scope/build_context"

	export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
	kubectl() {
		echo "$*" >> "$KUBECTL_LOG"
		if [ "$1" = "get" ] && [ "$2" = "namespace" ]; then
			return 0
		fi
		return 1
	}
	export -f kubectl

	export NP_OUTPUT_DIR="$(mktemp -d)"
	export SERVICE_PATH="$PROJECT_ROOT/k8s"

	export K8S_NAMESPACE="nullplatform"
	export DOMAIN="nullapps.io"
	export K8S_MODIFIERS="{}"

	export CONTEXT='{
		"scope": {
			"id": "123456",
			"slug": "production",
			"nrn": "nrn:organization=100:account=200:namespace=300:application=400",
			"domain": "test.nullapps.io",
			"capabilities": {
				"visibility": "public",
				"additional_ports": [{"port": 9090, "type": "GRPC", "traffic_manager_port": 19090}]
			}
		},
		"namespace": {"slug": "test-namespace"},
		"application": {"slug": "test-app"},
		"account": {"slug": "test-account"},
		"deployment": {"id": "789012"},
		"providers": {
			"cloud-providers": {
				"account": {"region": "us-east-1"},
				"networking": {"domain_name": "cloud-domain.io", "application_domain": "false"}
			},
			"container-orchestration": {
				"cluster": {"namespace": "default-namespace"},
				"gateway": {"public_name": "co-gateway-public", "private_name": "co-gateway-private"},
				"balancer": {"public_name": "co-balancer-public", "private_name": "co-balancer-private"}
			}
		}
	}'
}

teardown() {
	rm -rf "$NP_OUTPUT_DIR"
	unset -f kubectl
}

@test "build_context: injects resolved names into the context" {
	source "$SCRIPT"

	assert_equal "$(echo "$CONTEXT" | jq -r .names.deployment)" "d-123456-789012"
}

@test "build_context: injects per-port service names into additional_ports" {
	source "$SCRIPT"

	assert_equal "$(echo "$CONTEXT" | jq -r '.scope.capabilities.additional_ports[0].service_name')" "d-123456-789012-grpc-9090"
}

@test "build_context: resolves the scope ingress name with no trailing hyphen" {
	source "$SCRIPT"

	local ingress
	ingress="$(echo "$CONTEXT" | jq -r .names.scope_ingress)"
	assert_equal "$ingress" "k-8-s-production-123456-internet-facing"
	[[ "$ingress" != *- ]]
}

@test "build_context: names object does not carry additional_ports" {
	source "$SCRIPT"

	assert_equal "$(echo "$CONTEXT" | jq -r '.names | has("additional_ports")')" "false"
}

@test "build_context: queries namespace existence via kubectl" {
	source "$SCRIPT"

	assert_contains "$(cat "$KUBECTL_LOG")" "get namespace default-namespace"
}
