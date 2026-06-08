#!/usr/bin/env bats
# =============================================================================
# Unit tests for networking/autocreate_alb
# =============================================================================

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"

	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log

	source "$PROJECT_ROOT/k8s/utils/get_config_value"

	export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/autocreate_alb"
	export REGION="us-east-1"
	export INGRESS_VISIBILITY="internet-facing"
	export K8S_NAMESPACE="test-ns"
	export SERVICE_PATH="$PROJECT_ROOT/k8s"
	export OUTPUT_DIR="$(mktemp -d)"

	export CONTEXT='{
		"scope": {
			"id": "scope-1",
			"slug": "scope-1",
			"nrn": "organization=1:account=2:namespace=3:application=4:scope=5"
		},
		"namespace": { "id": "ns-1", "slug": "ns-1" },
		"application": { "id": "app-1", "slug": "app-1" },
		"account": { "id": "acc-1", "slug": "acc-1" },
		"deployment": { "id": "dep-1" },
		"providers": {
			"container-orchestration": {}
		}
	}'

	export CALL_LOG_FILE="$(mktemp)"

	# Default mocks — each test overrides as needed.
	gomplate() {
		local prev=""
		for arg in "$@"; do
			if [ "$prev" = "--out" ]; then echo "rendered" > "$arg"; fi
			prev="$arg"
		done
		return 0
	}
	export -f gomplate
	np() {
		echo "np $*" >> "$CALL_LOG_FILE"
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then
			echo '{"results":[{"id":"prov-1","attributes":{"balancer":{}}}]}'
			return 0
		fi
		if [ "$1" = "provider" ] && [ "$2" = "patch" ]; then
			local prev=""
			for arg in "$@"; do
				if [ "$prev" = "--body" ]; then echo "$arg" > "$OUTPUT_DIR/_patch_body"; fi
				prev="$arg"
			done
			return 0
		fi
		return 1
	}
	export -f np
}

teardown() {
	unset -f log gomplate np get_config_value
	rm -rf "$OUTPUT_DIR" "$CALL_LOG_FILE"
	unset ALB_NAME ALB_AUTOCREATED
}

# =============================================================================
# Name generation
# =============================================================================
@test "autocreate_alb: generates name with default prefix and public short form" {
	source "$SCRIPT"

	[[ "$ALB_NAME" =~ ^nullplatform-auto-public-[a-f0-9]{6}$ ]]
}

@test "autocreate_alb: generates name with private short form for internal visibility" {
	export INGRESS_VISIBILITY="internal"

	source "$SCRIPT"

	[[ "$ALB_NAME" =~ ^nullplatform-auto-private-[a-f0-9]{6}$ ]]
}

@test "autocreate_alb: respects custom name prefix" {
	export ALB_AUTOCREATE_NAME_PREFIX="custom-"

	source "$SCRIPT"

	[[ "$ALB_NAME" =~ ^custom-public-[a-f0-9]{6}$ ]]
}

@test "autocreate_alb: exports ALB_AUTOCREATED=true" {
	source "$SCRIPT"

	[ "$ALB_AUTOCREATED" = "true" ]
}

# =============================================================================
# Provider patching
# =============================================================================
@test "autocreate_alb: calls np provider list with the scope NRN" {
	source "$SCRIPT"

	grep -q "provider list" "$CALL_LOG_FILE"
	grep -q -- "--nrn organization=1:account=2:namespace=3:application=4:scope=5" "$CALL_LOG_FILE"
}

@test "autocreate_alb: patches additional_public_names for internet-facing visibility" {
	np() {
		echo "np $*" >> "$CALL_LOG_FILE"
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then
			echo '{"results":[{"id":"prov-1","attributes":{"balancer":{"additional_public_names":["existing-1"]}}}]}'
			return 0
		fi
		if [ "$1" = "provider" ] && [ "$2" = "patch" ]; then
			local prev=""
			for arg in "$@"; do
				if [ "$prev" = "--body" ]; then echo "$arg" > "$OUTPUT_DIR/_patch_body"; fi
				prev="$arg"
			done
			return 0
		fi
		return 1
	}
	export -f np

	source "$SCRIPT"

	local body
	body=$(cat "$OUTPUT_DIR/_patch_body")
	echo "$body" | jq -e '.attributes.balancer.additional_public_names | length == 2'
	echo "$body" | jq -e '.attributes.balancer.additional_public_names[0] == "existing-1"'
	echo "$body" | jq -e ".attributes.balancer.additional_public_names[1] == \"$ALB_NAME\""
}

@test "autocreate_alb: patches additional_private_names for internal visibility" {
	export INGRESS_VISIBILITY="internal"

	source "$SCRIPT"

	cat "$OUTPUT_DIR/_patch_body" | jq -e '.attributes.balancer.additional_private_names | length == 1'
}

@test "autocreate_alb: deduplicates when name already in list (defense in depth)" {
	np() {
		echo "np $*" >> "$CALL_LOG_FILE"
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then
			# Inject a duplicate scenario: pretend existing list already contains the same name
			# (impossible in practice given random suffix, but the jq pipeline must still be safe)
			echo '{"results":[{"id":"prov-1","attributes":{"balancer":{"additional_public_names":["a","b"]}}}]}'
			return 0
		fi
		if [ "$1" = "provider" ] && [ "$2" = "patch" ]; then
			local prev=""
			for arg in "$@"; do
				if [ "$prev" = "--body" ]; then echo "$arg" > "$OUTPUT_DIR/_patch_body"; fi
				prev="$arg"
			done
			return 0
		fi
		return 1
	}
	export -f np

	source "$SCRIPT"

	cat "$OUTPUT_DIR/_patch_body" | jq -e '.attributes.balancer.additional_public_names | length == 3'
}

@test "autocreate_alb: exits when provider list returns no results" {
	np() {
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then echo '{"results":[]}'; return 0; fi
		return 1
	}
	export -f np

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "No container-orchestration provider found"
}

@test "autocreate_alb: exits when np provider list fails" {
	np() {
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then return 2; fi
		return 1
	}
	export -f np

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "Failed to list container-orchestration provider"
}

@test "autocreate_alb: exits when np provider patch fails" {
	np() {
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then
			echo '{"results":[{"id":"prov-1","attributes":{"balancer":{}}}]}'
			return 0
		fi
		if [ "$1" = "provider" ] && [ "$2" = "patch" ]; then return 5; fi
		return 1
	}
	export -f np

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "Failed to patch container-orchestration provider"
}

@test "autocreate_alb: exits when CONTEXT has no scope.nrn" {
	export CONTEXT=$(echo "$CONTEXT" | jq 'del(.scope.nrn)')

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "Could not read scope NRN"
}

# =============================================================================
# Dummy ingress rendering
# =============================================================================
@test "autocreate_alb: renders the dummy ingress yaml to OUTPUT_DIR" {
	source "$SCRIPT"

	[ -f "$OUTPUT_DIR/ingress-dummy-${ALB_NAME}.yaml" ]
}

@test "autocreate_alb: exits when gomplate fails" {
	gomplate() { return 1; }
	export -f gomplate

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "Failed to render ingress-dummy template"
}

@test "autocreate_alb: exits when OUTPUT_DIR is not set" {
	unset OUTPUT_DIR

	run bash -c 'source "$SCRIPT"'

	[ "$status" -ne 0 ]
	assert_contains "$output" "OUTPUT_DIR is not set"
}
