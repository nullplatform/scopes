#!/usr/bin/env bats
# Renders the k8s service spec with gomplate and checks how VISIBILITY_OPTIONS filters the visibility
# options of the create form, and how it combines with DEFAULT_VISIBILITY.
# Every assertion ends in `|| fail`: a bare failing [[ ]] inside a loop does not fail the test on bash 3.2.

SPECS=(k8s)

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  export NRN="organization=1:account=2"
  unset DEFAULT_VISIBILITY VISIBILITY_OPTIONS

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

options() {
  echo "$output" | jq -c '[.attributes.schema.properties.visibility.oneOf[].const]'
}

without_visibility_options() {
  jq -S 'del(.attributes.schema.properties.visibility.default, .attributes.schema.properties.visibility.oneOf)'
}

@test "service spec: unset, empty or both VISIBILITY_OPTIONS (any order, case or spacing) render the same spec as unset" {
  for spec in "${SPECS[@]}"; do
    local expected
    expected="$(render "$spec")"
    for value in "" "  " "public,internal" "internal,public" " Public , PRIVATE " "public,internal,internal," "public,private"; do
      VISIBILITY_OPTIONS="$value" run render "$spec"
      [ "$status" -eq 0 ] || fail "$spec '$value': render failed: $output"
      [ "$output" = "$expected" ] || fail "$spec '$value': differs from the unset render"
    done
  done
}

@test "service spec: VISIBILITY_OPTIONS=internal offers only internal and defaults to it" {
  for spec in "${SPECS[@]}"; do
    local expected
    expected="$(render "$spec" | without_visibility_options)"
    for value in internal " Internal " private PRIVATE "internal,"; do
      VISIBILITY_OPTIONS="$value" run render "$spec"
      [ "$status" -eq 0 ] || fail "$spec '$value': render failed: $output"
      echo "$output" | jq -e . >/dev/null || fail "$spec '$value': invalid JSON"
      [ "$(visibility oneOf)" = '[{"const":"internal","title":"Private","description":"Only visible inside your organization"}]' ] \
        || fail "$spec '$value': oneOf $(visibility oneOf)"
      [ "$(visibility default)" = '"internal"' ] || fail "$spec '$value': default $(visibility default)"
      [ "$(echo "$output" | without_visibility_options)" = "$expected" ] || fail "$spec '$value': changes more than the visibility options"
    done
  done
}

@test "service spec: VISIBILITY_OPTIONS=public offers only public and defaults to it when DEFAULT_VISIBILITY is unset" {
  for spec in "${SPECS[@]}"; do
    VISIBILITY_OPTIONS=public run render "$spec"
    [ "$status" -eq 0 ] || fail "$spec: render failed: $output"
    echo "$output" | jq -e . >/dev/null || fail "$spec: invalid JSON"
    [ "$(options)" = '["public"]' ] || fail "$spec: options $(options)"
    [ "$(visibility default)" = '"public"' ] || fail "$spec: default $(visibility default)"
  done
}

@test "service spec: a DEFAULT_VISIBILITY listed in VISIBILITY_OPTIONS is kept" {
  for spec in "${SPECS[@]}"; do
    VISIBILITY_OPTIONS=internal DEFAULT_VISIBILITY=private run render "$spec"
    [ "$status" -eq 0 ] || fail "$spec internal/private: render failed: $output"
    [ "$(visibility default)" = '"internal"' ] || fail "$spec internal/private: default $(visibility default)"

    VISIBILITY_OPTIONS="public,internal" DEFAULT_VISIBILITY=public run render "$spec"
    [ "$status" -eq 0 ] || fail "$spec both/public: render failed: $output"
    [ "$(visibility default)" = '"public"' ] || fail "$spec both/public: default $(visibility default)"
  done
}

@test "service spec: unknown VISIBILITY_OPTIONS fails the render instead of guessing" {
  for spec in "${SPECS[@]}"; do
    for value in publik "internal,foo" "public;internal" "main account" "Internet"; do
      VISIBILITY_OPTIONS="$value" run render "$spec"
      [ "$status" -ne 0 ] || fail "$spec '$value': render succeeded"
      [[ "$output" == *"VISIBILITY_OPTIONS: unknown visibility"* ]] || fail "$spec '$value': message: $output"
      [[ "$output" == *"allowed: public, internal, private"* ]] || fail "$spec '$value': allowed values missing: $output"
    done
  done
}

@test "service spec: VISIBILITY_OPTIONS with no option left fails the render" {
  for spec in "${SPECS[@]}"; do
    for value in "," " , ,"; do
      VISIBILITY_OPTIONS="$value" run render "$spec"
      [ "$status" -ne 0 ] || fail "$spec '$value': render succeeded"
      [[ "$output" == *"VISIBILITY_OPTIONS: no visibility in"* ]] || fail "$spec '$value': message: $output"
    done
  done
}

@test "service spec: a DEFAULT_VISIBILITY missing from VISIBILITY_OPTIONS fails the render" {
  for spec in "${SPECS[@]}"; do
    VISIBILITY_OPTIONS=internal DEFAULT_VISIBILITY=public run render "$spec"
    [ "$status" -ne 0 ] || fail "$spec internal/public: render succeeded"
    [[ "$output" == *"DEFAULT_VISIBILITY:"*"public"*"is not one of the VISIBILITY_OPTIONS"* ]] || fail "$spec internal/public: message: $output"

    VISIBILITY_OPTIONS=public DEFAULT_VISIBILITY=private run render "$spec"
    [ "$status" -ne 0 ] || fail "$spec public/private: render succeeded"
    [[ "$output" == *"DEFAULT_VISIBILITY:"*"internal"*"is not one of the VISIBILITY_OPTIONS"* ]] || fail "$spec public/private: message: $output"

    VISIBILITY_OPTIONS=public run render "$spec"
    [ "$status" -eq 0 ] || fail "$spec public/unset: the single option should become the default: $output"
  done
}

@test "service spec: unknown DEFAULT_VISIBILITY still reports the unknown value when VISIBILITY_OPTIONS is set" {
  for spec in "${SPECS[@]}"; do
    VISIBILITY_OPTIONS=internal DEFAULT_VISIBILITY=publik run render "$spec"
    [ "$status" -ne 0 ] || fail "$spec: render succeeded"
    [[ "$output" == *"DEFAULT_VISIBILITY: unknown visibility"* ]] || fail "$spec: message: $output"
  done
}
