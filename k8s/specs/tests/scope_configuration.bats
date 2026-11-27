#!/usr/bin/env bats
# Checks k8s/specs/scope-configuration.json.tpl: it renders to valid JSON, its schema is well formed,
# and it declares every key the k8s scripts read from the scope-configurations provider.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TEMPLATE="$REPO_ROOT/k8s/specs/scope-configuration.json.tpl"
  NRN="organization=1:account=2"
}

# Rendered as tofu-modules' scope_definition does: no gomplate, the quoted NRN placeholder is replaced.
render() {
  sed -E 's/"\{\{ +env\.Getenv +"NRN" +\}\}"/"'"$NRN"'"/' "$TEMPLATE"
}

# Every path read as .providers["scope-configurations"].<path> under k8s/, tests excluded.
read_paths() {
  grep -rhoE '(providers\[\\?"scope-configurations\\?"\]|providers\.scope-configurations)\.[a-z_${}.]+' \
    "$REPO_ROOT/k8s" --exclude-dir=tests --exclude='*.md' \
    | sed -E 's/^[^]]*\]\.//; s/^providers\.scope-configurations\.//; s/\.$//' \
    | sed -E '/\$\{visibility\}/{ s/\$\{visibility\}/public/; p; s/_public_/_private_/; }' \
    | sort -u
}

# Schema paths down to the ones the scripts read (a key read whole, e.g. object_modifiers, is not descended).
schema_paths() {
  render | jq -r --argjson read "$(read_paths | jq -R . | jq -s .)" '
    def walk_props($prefix):
      (.properties // {}) | to_entries[] | ($prefix + [.key]) as $p | ($p | join(".")) as $path
      | $path, (if ($read | index($path)) then empty else (.value | walk_props($p)) end);
    .schema | walk_props([])'
}

@test "scope-configuration: renders to valid JSON with the NRN in visible_to" {
  render | jq -e . >/dev/null
  [ "$(render | jq -r '.visible_to[0]')" = "$NRN" ]
  [ "$(render | jq -r '.category')" = "scope-configurations" ]
}

@test "scope-configuration: renders the same with gomplate" {
  command -v gomplate >/dev/null 2>&1 || skip "gomplate not installed"
  [ "$(NRN="$NRN" gomplate -f "$TEMPLATE" | jq -S .)" = "$(render | jq -S .)" ]
}

@test "scope-configuration: the schema is well formed JSON Schema" {
  run bash -c "$(declare -f render); TEMPLATE='$TEMPLATE' NRN='$NRN' render"
  run jq -r '
    def types: ["object","array","string","integer","number","boolean"];
    [.schema | .. | objects | select(has("type"))
      | select(
          ((.type | IN(types[])) | not)
          or (has("properties") and .type != "object")
          or (has("items") and .type != "array")
          or (.type == "array" and (has("items") | not))
          or (has("enum") and ((.enum | type) != "array" or (.enum | length) == 0 or any(.enum[]; type != "string")))
          or (has("required") and (.required - (.properties // {} | keys) | length) > 0)
          or (has("pattern") and (.pattern | test(".") | not)))
    ] | length' < <(render)
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# A stored default would win over the container-orchestration provider and the agent's environment.
@test "scope-configuration: no property has a default" {
  [ "$(render | jq '[.schema | .. | objects | select(has("default"))] | length')" = "0" ]
}

@test "scope-configuration: declares every key the k8s scripts read" {
  local missing=() path
  while IFS= read -r path; do
    render | jq -e --arg p "$path" '.schema | getpath($p | split(".") | map("properties", .)) != null' >/dev/null \
      || missing+=("$path")
  done < <(read_paths)
  [ "$(read_paths | wc -l)" -gt 50 ]
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing from the spec: ${missing[*]}" >&2
    return 1
  fi
}

@test "scope-configuration: declares no key the k8s scripts do not read" {
  local stale=() path
  local read
  read=$(read_paths)
  while IFS= read -r path; do
    grep -qE "^${path//./\\.}(\.|$)" <<<"$read" || stale+=("$path")
  done < <(schema_paths)
  if [ "${#stale[@]}" -gt 0 ]; then
    echo "Not read by any script: ${stale[*]}" >&2
    return 1
  fi
}
