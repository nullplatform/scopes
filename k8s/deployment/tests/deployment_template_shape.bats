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

# Slice the file from "name: application" to the next container header,
# isolating the application container's block from the sidecars (which keep
# using container_cpu_in_millicores / container_memory_in_memory).
app_container_block() {
  awk '
    /^[[:space:]]+- name: application[[:space:]]*$/ { in_app=1 }
    in_app { print }
    /^[[:space:]]+terminationMessagePolicy:/ && in_app { exit }
  ' "$TEMPLATE"
}

@test "deployment template: application container limits.cpu uses cpu_millicores_limit" {
  block=$(app_container_block)
  echo "$block" | grep -E 'cpu:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.cpu_millicores_limit[[:space:]]*\}\}m' >/dev/null
}

@test "deployment template: application container limits.memory uses ram_memory_limit" {
  block=$(app_container_block)
  echo "$block" | grep -E 'memory:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.ram_memory_limit[[:space:]]*\}\}Mi' >/dev/null
}

@test "deployment template: application container requests.cpu still uses cpu_millicores" {
  block=$(app_container_block)
  echo "$block" | grep -E 'cpu:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.cpu_millicores[[:space:]]*\}\}m' >/dev/null
}

@test "deployment template: application container requests.memory still uses ram_memory" {
  block=$(app_container_block)
  echo "$block" | grep -E 'memory:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.ram_memory[[:space:]]*\}\}Mi' >/dev/null
}

@test "deployment template: sidecars still use container_cpu_in_millicores / container_memory_in_memory" {
  # Sidecars are everything BEFORE the application container block.
  before=$(awk '/^[[:space:]]+- name: application[[:space:]]*$/ {exit} {print}' "$TEMPLATE")
  echo "$before" | grep -F '{{ .container_cpu_in_millicores }}m' >/dev/null
  echo "$before" | grep -F '{{ .container_memory_in_memory }}Mi' >/dev/null
  # And sidecars must NOT have been switched to the new fields.
  ! echo "$before" | grep -F 'cpu_millicores_limit' >/dev/null
  ! echo "$before" | grep -F 'ram_memory_limit' >/dev/null
}
