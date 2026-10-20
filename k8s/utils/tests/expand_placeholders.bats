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

@test "unresolved_placeholders lists unknown and valueless placeholders without logging" {
  run unresolved_placeholders '{"a":"${np.nope}","b":"${np.dimension.region}","c":"${np.application_slug}"}' "$CTX"
  [ "$status" -eq 0 ] || false
  [ "$output" = "np.dimension.region, np.nope" ] || false
}

@test "unresolved_placeholders prints nothing when everything resolves" {
  run unresolved_placeholders '{"a":"${np.application_slug}","t":"{{ .x }}"}' "$CTX"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false
}

# =============================================================================
# Empty / null values are unresolved
# =============================================================================
@test "an empty value is unresolved for any key" {
  ctx=$(echo "$CTX" | jq '.scope.slug = ""')
  run expand_placeholders '{"x":"${np.scope_slug}"}' "$ctx"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *"np.scope_slug"* ]] || false
}

@test "an empty dimension value is unresolved" {
  ctx=$(echo "$CTX" | jq '.scope.dimensions.environment = ""')
  run unresolved_placeholders '{"x":"${np.dimension.environment}"}' "$ctx"
  [ "$status" -eq 0 ] || false
  [ "$output" = "np.dimension.environment" ] || false
}

@test "a null dimension value is unresolved, never the string null" {
  ctx=$(echo "$CTX" | jq '.scope.dimensions.environment = null')
  run expand_placeholders '{"x":"${np.dimension.environment}"}' "$ctx"
  [ "$status" -ne 0 ] || false
  [[ "$output" != *'"x":"null"'* ]] || false
  [[ "$output" == *"np.dimension.environment"* ]] || false
}

@test "a numeric dimension value is expanded as a string" {
  ctx=$(echo "$CTX" | jq '.scope.dimensions.tier = 2')
  run expand_placeholder_string 'tier-${np.dimension.tier}' "$ctx"
  [ "$status" -eq 0 ] || false
  [ "$output" = "tier-2" ] || false
}

# =============================================================================
# Malformed placeholders are unresolved (strict fails, never pass through)
# =============================================================================
@test "malformed placeholders fail expansion" {
  for tok in '${np.bad key}' '${np.}' '${np.app_slug }' '${np.unclosed'; do
    in=$(jq -n --arg s "$tok" '{x: $s}')
    run expand_placeholders "$in" "$CTX"
    [ "$status" -ne 0 ] || false
    [[ "$output" == *"$tok"* ]] || false
  done
}

@test "unresolved_placeholders lists malformed tokens verbatim" {
  run unresolved_placeholders '{"a":"${np.bad key}","b":"x-${np.unclosed","c":"${np.application_slug}"}' "$CTX"
  [ "$status" -eq 0 ] || false
  [ "$output" = '${np.bad key}, ${np.unclosed' ] || false
}

@test "a malformed token next to a valid one still fails" {
  run expand_placeholders '{"a":"${np.application_slug}-${np.}"}' "$CTX"
  [ "$status" -ne 0 ] || false
}

# =============================================================================
# Tolerant expansion: resolvable placeholders expand, unresolved entries drop
# =============================================================================
@test "expand_resolvable_placeholders drops unresolved map entries and expands the rest" {
  in='{"deployment":{"annotations":{"vault.hashicorp.com/agent-inject-secret-x":"kv/${np.nope}","app":"${np.application_slug}","plain":"v"}}}'
  run expand_resolvable_placeholders "$in" "$CTX"
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | jq -cS .)" = '{"deployment":{"annotations":{"app":"payments-api","plain":"v"}}}' ] || false
  [[ "$output" != *'${np.'* ]] || false
}

@test "expand_resolvable_placeholders drops unresolved list items" {
  run expand_resolvable_placeholders '{"l":["a","${np.nope}","${np.scope_slug}"]}' "$CTX"
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | jq -c .)" = '{"l":["a","development"]}' ] || false
}

@test "expand_resolvable_placeholders drops malformed tokens" {
  run expand_resolvable_placeholders '{"a":"${np.unclosed","b":"${np.app_slug }","c":"ok"}' "$CTX"
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | jq -c .)" = '{"c":"ok"}' ] || false
}

@test "expand_resolvable_placeholders leaves json without placeholders unchanged" {
  in='{"deployment":{"labels":{"a":"b"},"n":3,"t":"{{ .x }}"}}'
  run expand_resolvable_placeholders "$in" "$CTX"
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | jq -c .)" = "$(echo "$in" | jq -c .)" ] || false
}

@test "unresolved_placeholder_paths names every dropped path" {
  in='{"deployment":{"annotations":{"vault.hashicorp.com/agent-inject-secret-x":"${np.nope}","ok":"${np.scope_slug}"}},"l":["${np.}"]}'
  run unresolved_placeholder_paths "$in" "$CTX"
  [ "$status" -eq 0 ] || false
  [ "$output" = 'deployment.annotations."vault.hashicorp.com/agent-inject-secret-x", l[0]' ] || false
}

# =============================================================================
# Failure handling: a malformed document or context never dies with a raw jq error
# =============================================================================
@test "a malformed context logs a clear error and returns non-zero" {
  for fn in expand_placeholders expand_resolvable_placeholders unresolved_placeholders unresolved_placeholder_paths; do
    run "$fn" '{"x":"${np.application_slug}"}' 'not-json'
    [ "$status" -ne 0 ] || false
    [[ "$output" == *"❌ Could not read the scope context to resolve placeholders"* ]] || false
  done
}

@test "a malformed document logs a clear error and returns non-zero" {
  for fn in expand_placeholders expand_resolvable_placeholders unresolved_placeholders unresolved_placeholder_paths; do
    run "$fn" '{"x":' "$CTX"
    [ "$status" -ne 0 ] || false
    [[ "$output" == *"❌ Could not scan placeholders: the document is not valid JSON"* ]] || false
  done
}

@test "the unknown-placeholder hint lists the supported keys from the values map" {
  run expand_placeholders '{"x":"${np.app_slug}"}' "$CTX"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *'${np.account_slug} ${np.namespace_slug} ${np.application_slug} ${np.repository_name} ${np.scope_slug} ${np.scope_id} ${np.k8s_namespace} ${np.dimension.<key>}'* ]] || false
  [[ "$output" == *"Scope dimensions: country, environment"* ]] || false
}

# =============================================================================
# repository_name: scp-style URLs
# =============================================================================
@test "repository_name handles scp-style URLs" {
  for url in 'git@github.com:acme/repo.git' 'git@github.com:repo.git' 'git@github.com:acme/repo'; do
    ctx=$(echo "$CTX" | jq --arg u "$url" '.application.repository_url = $u')
    run expand_placeholder_string '${np.repository_name}' "$ctx"
    [ "$status" -eq 0 ] || false
    [ "$output" = "repo" ] || false
  done
}
