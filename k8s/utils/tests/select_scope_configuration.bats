#!/usr/bin/env bats
# Unit tests for k8s/utils/select_scope_configuration

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { echo "$1 $2"; }
  source "$PROJECT_ROOT/k8s/utils/get_config_value"
  source "$PROJECT_ROOT/k8s/utils/select_scope_configuration"
  unset SCOPE_CONFIGURATION_SLUG

  # The CLI's top level is a lambda provider (namespace NRN beats the account-level k8s one).
  export CONTEXT='{"providers": {"scope-configurations": {
    "lambda": {"runtime": "nodejs"},
    "networking": {"service_to_service": {"enabled": "false"}},
    "containers-s2s-e2e": {"networking": {"service_to_service": {"enabled": "true", "mode": "dedicated"}}},
    "lambda-spec": {"lambda": {"runtime": "nodejs"}, "networking": {"service_to_service": {"enabled": "false"}}}
  }}}'
}

read_enabled() {
  get_config_value --provider '.providers["scope-configurations"].networking.service_to_service.enabled' --default "unset"
}

@test "select_scope_configuration: the slug's provider replaces a different top level" {
  export SCOPE_CONFIGURATION_SLUG=containers-s2s-e2e

  np_select_scope_configuration

  assert_equal "$(read_enabled)" "true"
  assert_equal "$(get_config_value --provider '.providers["scope-configurations"].networking.service_to_service.mode')" "dedicated"
  assert_equal "$(echo "$CONTEXT" | jq -r '.providers["scope-configurations"] | has("lambda")')" "false"
}

@test "select_scope_configuration: runs once per context" {
  export SCOPE_CONFIGURATION_SLUG=containers-s2s-e2e
  np_select_scope_configuration
  local once="$CONTEXT"

  run np_select_scope_configuration
  np_select_scope_configuration

  [[ "$output" != *"warn"* ]] || false
  assert_equal "$CONTEXT" "$once"
}

@test "select_scope_configuration: a slug with no provider keeps the top level and warns" {
  export SCOPE_CONFIGURATION_SLUG=containers-other
  local before="$CONTEXT"

  run np_select_scope_configuration

  assert_contains "$output" "No scope-configurations provider of spec 'containers-other'"
  np_select_scope_configuration >/dev/null
  assert_equal "$CONTEXT" "$before"
  assert_equal "$(read_enabled)" "false"
}

@test "select_scope_configuration: unset leaves the context byte-identical" {
  local before="$CONTEXT"

  run np_select_scope_configuration
  np_select_scope_configuration

  assert_equal "$output" ""
  assert_equal "$CONTEXT" "$before"
}

@test "select_scope_configuration: the scope build_context selects it before reading any setting" {
  run grep -n 'np_select_scope_configuration\|get_config_value \\' "$PROJECT_ROOT/k8s/scope/build_context"
  [[ "$(echo "$output" | head -1)" == *"np_select_scope_configuration"* ]] || false
  run grep -c 'np_select_scope_configuration' "$PROJECT_ROOT/k8s/utils/resolve_k8s_namespace"
  assert_equal "$output" "1"
}
