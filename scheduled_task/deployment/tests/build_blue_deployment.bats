#!/usr/bin/env bats
# =============================================================================
# Unit tests for scheduled_task/deployment/build_blue_deployment
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  source "$PROJECT_ROOT/k8s/utils/get_config_value"
  source "$PROJECT_ROOT/k8s/naming/resolve_names"
  export -f get_config_value np_name_sanitize np_name_cap np_trim_segments \
    np_naming_validate_pattern \
    np_naming_resolve_path np_name_render np_naming_strategy np_naming_resolve np_naming_roles_ids \
    np_naming_emit np_naming_roles_patterned np_naming_lookup np_naming_discover_blue \
    np_naming_discover_scope
  unset NAMING_STRATEGY

  export OVERRIDES_PATH="$PROJECT_ROOT/scheduled_task"
  export DEPLOYMENT_ID="deploy-green-123"

  export CONTEXT='{
    "blue_replicas": 2,
    "scope": {
      "current_active_deployment": "deploy-old-456"
    },
    "deployment": {
      "id": "deploy-green-123"
    }
  }'
}

teardown() {
  unset CONTEXT
}

@test "build_blue_deployment: renders the blue CronJob's own name, not green's" {
  local raw_context
  raw_context="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal.json")"

  local resolved_names
  resolved_names="$(CONTEXT="$raw_context" np_naming_resolve)"

  export CONTEXT="$(echo "$raw_context" | jq \
    --argjson names "$resolved_names" \
    '. + {names: ($names | del(.additional_ports))}
     | if ($names.additional_ports | length) > 0
       then .scope.capabilities.additional_ports = $names.additional_ports
       else . end
     | .scope.current_active_deployment = "789011"')"

  export SCOPE_ID="$(echo "$CONTEXT" | jq -r .scope.id)"
  export DEPLOYMENT_ID="$(echo "$CONTEXT" | jq -r .deployment.id)"
  export OVERRIDES_PATH="$PROJECT_ROOT/scheduled_task"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/output"
  mkdir -p "$OUTPUT_DIR"
  export DEPLOYMENT_TEMPLATE="$PROJECT_ROOT/scheduled_task/deployment/templates/deployment.yaml.tpl"
  export SECRET_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/secret.yaml.tpl"
  export SECRET_FILES_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/secret-files.yaml.tpl"

  source "$PROJECT_ROOT/scheduled_task/deployment/build_blue_deployment"

  rendered_name="$(yq -N '.metadata.name' "$OUTPUT_DIR/deployment-$SCOPE_ID-789011.yaml")"
  assert_equal "$rendered_name" "job-123456-789011"
}
