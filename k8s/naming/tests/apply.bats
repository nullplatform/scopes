#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
	export -f log
	source "$PROJECT_ROOT/k8s/utils/get_config_value"
	source "$PROJECT_ROOT/k8s/naming/resolve_names"

	export CONTEXT="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal.json" \
		| jq '.scope.current_active_deployment = "789012"')"
	unset NAMING_STRATEGY DEPLOYMENT_ID

	kubectl() {
		case "$*" in
			*"get service"*|*"get deployment"*) echo '{"items":[]}' ;;
			*"items[0]"*)
				echo 'error: error executing jsonpath "{.items[0].metadata.name}": array index out of bounds: index 0, length 0'
				return 1
				;;
			*) echo "" ;;
		esac
	}
}

@test "np_naming_apply_to_context: succeeds for a scope with no hpa, pdb or cronjob" {
	local result
	if np_naming_apply_to_context; then result=0; else result=$?; fi

	[ "$result" -eq 0 ]
}

@test "np_naming_apply_to_context: falls back to the computed names when hpa, pdb and cronjob are all absent" {
	local result
	if np_naming_apply_to_context; then result=0; else result=$?; fi
	[ "$result" -eq 0 ]

	run jq -r '.names.hpa, .names.pdb, .names.cronjob' <<< "$CONTEXT"
	assert_equal "$(echo "$output" | sed -n 1p)" "hpa-d-123456-789012"
	assert_equal "$(echo "$output" | sed -n 2p)" "pdb-d-123456-789012"
	assert_equal "$(echo "$output" | sed -n 3p)" "job-123456-789012"
}
