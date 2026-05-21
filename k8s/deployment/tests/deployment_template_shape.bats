#!/usr/bin/env bats
# =============================================================================
# Structural tests for the deployment template.
# Verifies the application container's resources block uses the right
# capability for request vs limit. CLIEN-781.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/deployment.yaml.tpl"
}

# Slice the file from "name: application" up to the application container's
# terminationMessagePolicy, isolating it from the sidecars (which keep using
# container_cpu_in_millicores / container_memory_in_memory).
app_container_block() {
  awk '
    /^[[:space:]]+- name: application[[:space:]]*$/ { in_app=1 }
    in_app { print }
    /^[[:space:]]+terminationMessagePolicy:/ && in_app { exit }
  ' "$TEMPLATE"
}

# Everything BEFORE the application container — the sidecar definitions.
sidecars_block() {
  awk '/^[[:space:]]+- name: application[[:space:]]*$/ {exit} {print}' "$TEMPLATE"
}

@test "deployment template: application container limits.cpu uses cpu_millicores_limit" {
  grep -qE 'cpu:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.cpu_millicores_limit[[:space:]]*\}\}m' <<<"$(app_container_block)"
}

@test "deployment template: application container limits.memory uses ram_memory_limit" {
  grep -qE 'memory:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.ram_memory_limit[[:space:]]*\}\}Mi' <<<"$(app_container_block)"
}

@test "deployment template: application container requests.cpu still uses cpu_millicores" {
  grep -qE 'cpu:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.cpu_millicores[[:space:]]*\}\}m' <<<"$(app_container_block)"
}

@test "deployment template: application container requests.memory still uses ram_memory" {
  grep -qE 'memory:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.ram_memory[[:space:]]*\}\}Mi' <<<"$(app_container_block)"
}

@test "deployment template: sidecars still use container_cpu_in_millicores / container_memory_in_memory" {
  local sidecars
  sidecars=$(sidecars_block)
  grep -qF '{{ .container_cpu_in_millicores }}m' <<<"$sidecars"
  grep -qF '{{ .container_memory_in_memory }}Mi' <<<"$sidecars"
  # And sidecars must NOT have been switched to the new fields.
  ! grep -qF 'cpu_millicores_limit' <<<"$sidecars"
  ! grep -qF 'ram_memory_limit' <<<"$sidecars"
}
