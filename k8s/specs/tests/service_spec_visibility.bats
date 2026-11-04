#!/usr/bin/env bats
# Renders the k8s, azure, azure-aro and onprem service specs with gomplate and
# checks the visibility default and the input validation of DEFAULT_VISIBILITY.

SPECS=(k8s azure azure-aro onprem)

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  export NRN="organization=1:account=2"
  unset DEFAULT_VISIBILITY

  if ! command -v gomplate >/dev/null 2>&1; then
    skip "gomplate not installed"
  fi
}

render() {
  gomplate -f "$REPO_ROOT/$1/specs/service-spec.json.tpl"
}

visibility() {
  echo "$output" | jq -c ".attributes.schema.properties.visibility.$1"
}

@test "service spec: unset DEFAULT_VISIBILITY defaults to internal and keeps both options" {
  for spec in "${SPECS[@]}"; do
    run render "$spec"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
    [ "$(visibility default)" = '"internal"' ]
    [ "$(visibility oneOf)" = '[{"const":"public","title":"Internet","description":"Public, reachable by anyone"},{"const":"internal","title":"Private","description":"Only visible inside your organization"}]' ]
    [ "$(visibility editableOn)" = '["create"]' ]
  done
}

@test "service spec: empty, internal and private (any case or spacing) render the same spec as unset" {
  for spec in "${SPECS[@]}"; do
    local expected
    expected="$(render "$spec")"
    for value in "" "  " internal Internal " INTERNAL " private Private; do
      DEFAULT_VISIBILITY="$value" run render "$spec"
      [ "$status" -eq 0 ]
      [ "$output" = "$expected" ]
    done
  done
}

@test "service spec: public (any case or spacing) only changes the visibility default" {
  for spec in "${SPECS[@]}"; do
    local expected
    expected="$(render "$spec" | jq -S 'del(.attributes.schema.properties.visibility.default)')"
    for value in public Public " PUBLIC "; do
      DEFAULT_VISIBILITY="$value" run render "$spec"
      [ "$status" -eq 0 ]
      [ "$(visibility default)" = '"public"' ]
      [ "$(echo "$output" | jq -S 'del(.attributes.schema.properties.visibility.default)')" = "$expected" ]
    done
  done
}

@test "service spec: unknown DEFAULT_VISIBILITY fails the render instead of guessing" {
  for spec in "${SPECS[@]}"; do
    for value in publik publc intern "public,internal" "main account"; do
      DEFAULT_VISIBILITY="$value" run render "$spec"
      [ "$status" -ne 0 ]
      [[ "$output" == *"DEFAULT_VISIBILITY: unknown visibility"* ]]
      [[ "$output" == *"allowed: public, internal, private"* ]]
    done
  done
}
