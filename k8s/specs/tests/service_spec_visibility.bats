#!/usr/bin/env bats
# Renders the k8s, azure, azure-aro and onprem service specs with gomplate and checks the
# DEFAULT_VISIBILITY default, canonicalization and validation.
# Every assertion ends in `|| fail`: a bare failing [[ ]] inside a loop does not fail the test on bash 3.2.

SPECS=(k8s azure azure-aro onprem)

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  export NRN="organization=1:account=2"
  unset DEFAULT_VISIBILITY

  if ! command -v gomplate >/dev/null 2>&1; then
    skip "gomplate not installed"
  fi
}

fail() {
  echo "$*" >&2
  return 1
}

render() {
  gomplate -f "$REPO_ROOT/$1/specs/service-spec.json.tpl"
}

visibility() {
  echo "$output" | jq -c ".attributes.schema.properties.visibility.$1"
}

without_default() {
  jq -S 'del(.attributes.schema.properties.visibility.default)'
}

@test "service spec: unset DEFAULT_VISIBILITY defaults to internal and keeps both options" {
  for spec in "${SPECS[@]}"; do
    run render "$spec"
    [ "$status" -eq 0 ] || fail "$spec: render failed: $output"
    echo "$output" | jq -e . >/dev/null || fail "$spec: invalid JSON"
    [ "$(visibility default)" = '"internal"' ] || fail "$spec: default $(visibility default)"
    [ "$(visibility oneOf)" = '[{"const":"public","title":"Internet","description":"Public, reachable by anyone"},{"const":"internal","title":"Private","description":"Only visible inside your organization"}]' ] \
      || fail "$spec: oneOf $(visibility oneOf)"
    [ "$(visibility editableOn)" = '["create"]' ] || fail "$spec: editableOn $(visibility editableOn)"
  done
}

@test "service spec: empty, internal and private (any case or spacing) render the same spec as unset" {
  for spec in "${SPECS[@]}"; do
    local expected
    expected="$(render "$spec")"
    for value in "" "  " internal Internal " INTERNAL " private Private; do
      DEFAULT_VISIBILITY="$value" run render "$spec"
      [ "$status" -eq 0 ] || fail "$spec '$value': render failed: $output"
      [ "$output" = "$expected" ] || fail "$spec '$value': differs from the unset render"
    done
  done
}

@test "service spec: public (any case or spacing) only changes the visibility default" {
  for spec in "${SPECS[@]}"; do
    local expected
    expected="$(render "$spec" | without_default)"
    for value in public Public " PUBLIC "; do
      DEFAULT_VISIBILITY="$value" run render "$spec"
      [ "$status" -eq 0 ] || fail "$spec '$value': render failed: $output"
      [ "$(visibility default)" = '"public"' ] || fail "$spec '$value': default $(visibility default)"
      [ "$(echo "$output" | without_default)" = "$expected" ] || fail "$spec '$value': changes more than the default"
    done
  done
}

@test "service spec: every accepted value renders a default listed in oneOf" {
  for spec in "${SPECS[@]}"; do
    for value in unset public internal private; do
      if [ "$value" = unset ]; then run render "$spec"; else DEFAULT_VISIBILITY="$value" run render "$spec"; fi
      [ "$status" -eq 0 ] || fail "$spec '$value': render failed: $output"
      echo "$output" | jq -e '.attributes.schema.properties.visibility | .default as $d | [.oneOf[].const] | index($d) != null' >/dev/null \
        || fail "$spec '$value': default $(visibility default) not in oneOf"
    done
  done
}

@test "service spec: unknown DEFAULT_VISIBILITY fails the render instead of guessing" {
  for spec in "${SPECS[@]}"; do
    for value in publik publc intern foo "public,internal" "main account"; do
      DEFAULT_VISIBILITY="$value" run render "$spec"
      [ "$status" -ne 0 ] || fail "$spec '$value': render succeeded"
      [[ "$output" == *"DEFAULT_VISIBILITY: unknown visibility"* ]] || fail "$spec '$value': message: $output"
      [[ "$output" == *"allowed: public, internal, private"* ]] || fail "$spec '$value': allowed values missing: $output"
    done
  done
}
