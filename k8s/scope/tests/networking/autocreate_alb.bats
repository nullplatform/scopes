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
	export -f get_config_value

	export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/autocreate_alb"
	export REGION="us-east-1"
	export INGRESS_VISIBILITY="internet-facing"
	export K8S_NAMESPACE="test-ns"
	export SERVICE_PATH="$PROJECT_ROOT/k8s"
	export DOMAIN="nullapps.io"
	export OUTPUT_DIR="$(mktemp -d)"
	export PATCH_BODY_FILE="$OUTPUT_DIR/_patch_body"

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
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then
			echo '{"results":[{"id":"prov-1","attributes":{"balancer":{}}}]}'
			return 0
		fi
		if [ "$1" = "provider" ] && [ "$2" = "patch" ]; then
			local prev=""
			for arg in "$@"; do
				if [ "$prev" = "--body" ]; then echo "$arg" > "$PATCH_BODY_FILE"; fi
				prev="$arg"
			done
			return 0
		fi
		return 1
	}
	export -f np
	export -f gomplate
}

teardown() {
	unset -f log gomplate np get_config_value
	rm -rf "$OUTPUT_DIR"
	unset ALB_NAME ALB_AUTOCREATED
}

# =============================================================================
# Happy path — full log sequence (info logs only; debug needs LOG_LEVEL=debug)
# =============================================================================
@test "autocreate_alb: full happy-path log sequence (default prefix, public visibility)" {
	run bash -c 'export LOG_LEVEL=debug; source "$SCRIPT"; echo "ALB_NAME=$ALB_NAME ALB_AUTOCREATED=$ALB_AUTOCREATED"'

	assert_equal "$status" "0"
	# First log: name generated + visibility echoed
	[[ "$output" =~ "🔧 Autocreating ALB 'nullplatform-auto-public-"[a-f0-9]{6}"' (visibility=internet-facing)" ]]
	# Provider patch log (field name appears explicitly)
	[[ "$output" =~ "📝 Registering ALB 'nullplatform-auto-public-"[a-f0-9]{6}"' in container-orchestration provider (additional_public_names)" ]]
	# Render confirmation (debug)
	assert_contains "$output" "📝 Rendered dummy ingress to $OUTPUT_DIR/ingress-dummy-"
	# Exports
	[[ "$output" =~ "ALB_NAME=nullplatform-auto-public-"[a-f0-9]{6}" ALB_AUTOCREATED=true" ]]
}

@test "autocreate_alb: internal visibility selects additional_private_names field in registration log" {
	export INGRESS_VISIBILITY="internal"

	run bash -c 'source "$SCRIPT"; echo "ALB_NAME=$ALB_NAME"'

	assert_equal "$status" "0"
	[[ "$output" =~ "🔧 Autocreating ALB 'nullplatform-auto-private-"[a-f0-9]{6}"' (visibility=internal)" ]]
	[[ "$output" =~ "📝 Registering ALB 'nullplatform-auto-private-"[a-f0-9]{6}"' in container-orchestration provider (additional_private_names)" ]]
}

@test "autocreate_alb: custom prefix flows into both autocreate and registration logs" {
	export ALB_AUTOCREATE_NAME_PREFIX="custom-"

	run bash -c 'source "$SCRIPT"; echo "ALB_NAME=$ALB_NAME"'

	assert_equal "$status" "0"
	[[ "$output" =~ "🔧 Autocreating ALB 'custom-public-"[a-f0-9]{6}"' (visibility=internet-facing)" ]]
	[[ "$output" =~ "ALB_NAME=custom-public-"[a-f0-9]{6} ]]
}

# =============================================================================
# Provider patch shape
# =============================================================================
@test "autocreate_alb: patches additional_public_names preserving existing entries" {
	np() {
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then
			echo '{"results":[{"id":"prov-1","attributes":{"balancer":{"additional_public_names":["existing-1"]}}}]}'
			return 0
		fi
		if [ "$1" = "provider" ] && [ "$2" = "patch" ]; then
			local prev=""
			for arg in "$@"; do
				if [ "$prev" = "--body" ]; then echo "$arg" > "$PATCH_BODY_FILE"; fi
				prev="$arg"
			done
			return 0
		fi
		return 1
	}
	export -f np

	source "$SCRIPT"

	local body
	body=$(cat "$PATCH_BODY_FILE")
	echo "$body" | jq -e '.attributes.balancer.additional_public_names | length == 2'
	echo "$body" | jq -e '.attributes.balancer.additional_public_names[0] == "existing-1"'
	echo "$body" | jq -e ".attributes.balancer.additional_public_names[1] == \"$ALB_NAME\""
}

@test "autocreate_alb: patches additional_private_names for internal visibility" {
	export INGRESS_VISIBILITY="internal"

	source "$SCRIPT"

	cat "$PATCH_BODY_FILE" | jq -e '.attributes.balancer.additional_private_names | length == 1'
}

@test "autocreate_alb: deduplicates name in the patched list" {
	np() {
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then
			echo '{"results":[{"id":"prov-1","attributes":{"balancer":{"additional_public_names":["a","b"]}}}]}'
			return 0
		fi
		if [ "$1" = "provider" ] && [ "$2" = "patch" ]; then
			local prev=""
			for arg in "$@"; do
				if [ "$prev" = "--body" ]; then echo "$arg" > "$PATCH_BODY_FILE"; fi
				prev="$arg"
			done
			return 0
		fi
		return 1
	}
	export -f np

	source "$SCRIPT"

	cat "$PATCH_BODY_FILE" | jq -e '.attributes.balancer.additional_public_names | length == 3'
}

# =============================================================================
# Error paths — full failure log
# =============================================================================
@test "autocreate_alb: exits with full log when provider list returns no results" {
	np() {
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then echo '{"results":[]}'; return 0; fi
		return 1
	}
	export -f np

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "1"
	[[ "$output" =~ "🔧 Autocreating ALB 'nullplatform-auto-public-"[a-f0-9]{6}"' (visibility=internet-facing)" ]]
	assert_contains "$output" "❌ No container-orchestration provider found for NRN 'organization=1:account=2:namespace=3:application=4:scope=5'"
}

@test "autocreate_alb: exits with full log when np provider list fails" {
	np() {
		if [ "$1" = "provider" ] && [ "$2" = "list" ]; then return 2; fi
		return 1
	}
	export -f np

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "1"
	assert_contains "$output" "❌ Failed to list container-orchestration provider for NRN 'organization=1:account=2:namespace=3:application=4:scope=5'"
}

@test "autocreate_alb: exits with full log when np provider patch fails" {
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

	assert_equal "$status" "1"
	[[ "$output" =~ "📝 Registering ALB 'nullplatform-auto-public-"[a-f0-9]{6}"' in container-orchestration provider (additional_public_names)" ]]
	assert_contains "$output" "❌ Failed to patch container-orchestration provider with new ALB"
	assert_contains "$output" "💡 Possible causes: agent lacks write permission on the provider, or NP_TOKEN/NULLPLATFORM_API_KEY is missing"
}

@test "autocreate_alb: exits with full log when CONTEXT has no scope.nrn" {
	export CONTEXT=$(echo "$CONTEXT" | jq 'del(.scope.nrn)')

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "1"
	assert_contains "$output" "❌ Could not read scope NRN from CONTEXT — cannot patch provider"
}

@test "autocreate_alb: exits with full log when gomplate fails to render" {
	gomplate() { return 1; }
	export -f gomplate

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "1"
	assert_contains "$output" "❌ Failed to render ingress-dummy template"
	assert_contains "$output" "📋 Template: $SERVICE_PATH/scope/templates/ingress-dummy.yaml.tpl"
}

@test "autocreate_alb: exits with full log when OUTPUT_DIR is not set" {
	unset OUTPUT_DIR

	run bash -c 'source "$SCRIPT"'

	assert_equal "$status" "1"
	assert_contains "$output" "❌ OUTPUT_DIR is not set — autocreate_alb must run after OUTPUT_DIR is exported"
}

# =============================================================================
# Side effects — rendered YAML file
# =============================================================================
@test "autocreate_alb: renders the dummy ingress yaml file inside OUTPUT_DIR" {
	source "$SCRIPT"

	[ -f "$OUTPUT_DIR/ingress-dummy-${ALB_NAME}.yaml" ]
}
