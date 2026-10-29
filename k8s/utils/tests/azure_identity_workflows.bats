#!/usr/bin/env bats
# =============================================================================
# Structural tests: every k8s workflow that assumes an AWS role also picks the
# Azure managed identity, right after `assume role` and before `build context`,
# and propagates the two env vars the step exports.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  WORKFLOWS=$(grep -rl 'utils/assume_role_step' "$PROJECT_ROOT/k8s" --include='*.yaml' | grep -v '/tests/' | sort)
}

@test "azure_identity_step: wired right after assume role in every workflow that assumes a role" {
  [ -n "$WORKFLOWS" ]
  for wf in $WORKFLOWS; do
    assume_line=$(grep -n 'utils/assume_role_step' "$wf" | head -1 | cut -d: -f1)
    azure_line=$(grep -n 'utils/azure_identity_step' "$wf" | head -1 | cut -d: -f1)
    context_line=$(grep -n 'name: build context' "$wf" | head -1 | cut -d: -f1)
    if [ -z "$azure_line" ]; then
      echo "missing azure identity step: $wf"
      return 1
    fi
    if [ "$azure_line" -le "$assume_line" ] || [ "$azure_line" -ge "$context_line" ]; then
      echo "azure identity step out of order: $wf"
      return 1
    fi
  done
}

@test "azure_identity_step: every workflow propagates AZURE_CLIENT_ID and AZURE_CLIENT_SECRET" {
  for wf in $WORKFLOWS; do
    block=$(grep -A7 'utils/azure_identity_step' "$wf")
    assert_contains "$block" "- name: AZURE_CLIENT_ID"
    assert_contains "$block" "- name: AZURE_CLIENT_SECRET"
  done
}
