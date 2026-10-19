#!/usr/bin/env bats
# =============================================================================
# Unit tests for expand_placeholders - ${np.<key>} expansion from scope context
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  log() { echo "$@" >&2; }; export -f log
  source "$PROJECT_ROOT/k8s/utils/expand_placeholders"
  CTX='{"account":{"slug":"acme"},"namespace":{"slug":"payments"},
        "application":{"slug":"payments-api","repository_url":"https://github.com/acme/payments-api.git"},
        "scope":{"slug":"development","id":42,"dimensions":{"environment":"development","country":"cl"}},
        "k8s_namespace":"payments"}'
}

@test "expands every supported placeholder" {
  run expand_placeholders '{"a":"${np.account_slug}/${np.namespace_slug}/${np.application_slug}/${np.repository_name}/${np.scope_slug}/${np.scope_id}/${np.k8s_namespace}/${np.dimension.environment}"}' "$CTX"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .a)" = "acme/payments/payments-api/payments-api/development/42/payments/development" ]
}

@test "leaves Go template syntax untouched" {
  in='{"t":"{{- with secret \"kv/data/x\" -}}{{ .Data.data.k }}{{ end }}{{range .}}{{end}}"}'
  run expand_placeholders "$in" "$CTX"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c .)" = "$(echo "$in" | jq -c .)" ]
}

@test "expands nested maps and keeps non-strings" {
  run expand_placeholders '{"deployment":{"annotations":{"x":"${np.application_slug}"},"n":3,"b":true}}' "$CTX"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c .)" = '{"deployment":{"annotations":{"x":"payments-api"},"n":3,"b":true}}' ]
}

@test "json without placeholders is returned unchanged" {
  run expand_placeholders '{"global":{"labels":{"team":"core"}}}' "$CTX"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c .)" = '{"global":{"labels":{"team":"core"}}}' ]
}

@test "unknown placeholder fails listing the supported ones" {
  run expand_placeholders '{"x":"${np.app_slug}"}' "$CTX"
  [ "$status" -ne 0 ]
  [[ "$output" == *"np.app_slug"* ]] || false
  [[ "$output" == *"application_slug"* ]] || false
}

@test "missing dimension fails" {
  run expand_placeholders '{"x":"${np.dimension.region}"}' "$CTX"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dimension.region"* ]] || false
}

@test "repository_name strips .git and path" {
  ctx=$(echo "$CTX" | jq '.application.repository_url="https://github.com/acme/foo-bar"')
  run expand_placeholder_string '${np.repository_name}' "$ctx"
  [ "$status" -eq 0 ]; [ "$output" = "foo-bar" ]
}

@test "string dimensions value is treated as no dimensions" {
  ctx=$(echo "$CTX" | jq '.scope.dimensions="production"')
  run expand_placeholders '{"x":"${np.application_slug}"}' "$ctx"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .x)" = "payments-api" ]
  run expand_placeholders '{"x":"${np.dimension.environment}"}' "$ctx"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dimension.environment"* ]] || false
}

@test "expand_placeholder_string fails on unknown placeholder" {
  run expand_placeholder_string '${np.app_slug}' "$CTX"
  [ "$status" -ne 0 ]
  [[ "$output" == *"np.app_slug"* ]] || false
}

@test "repository_name ignores a trailing slash" {
  ctx=$(echo "$CTX" | jq '.application.repository_url="https://github.com/acme/foo/"')
  run expand_placeholder_string '${np.repository_name}' "$ctx"
  [ "$status" -eq 0 ]; [ "$output" = "foo" ]
}

@test "missing repository_url makes repository_name fail" {
  ctx=$(echo "$CTX" | jq 'del(.application.repository_url)')
  run expand_placeholders '{"x":"${np.repository_name}"}' "$ctx"
  [ "$status" -ne 0 ]
  [[ "$output" == *"np.repository_name"* ]] || false
}
