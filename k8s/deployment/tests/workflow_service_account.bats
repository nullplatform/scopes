#!/usr/bin/env bats
# =============================================================================
# Structural tests: deployments that apply a Deployment manifest ensure the
# per-scope service account exists first (scopes created before the feature was
# enabled have none), and scheduled_task inherits the step unchanged.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export INITIAL="$PROJECT_ROOT/k8s/deployment/workflows/initial.yaml"
}

step_index() {
  yq -r ".steps | to_entries | map(select(.value.name == \"$2\")) | .[0].key // \"\"" "$1"
}

@test "initial: ensure service account runs before route traffic and create deployment" {
  ensure=$(step_index "$INITIAL" "ensure service account")
  route=$(step_index "$INITIAL" "route traffic")
  create=$(step_index "$INITIAL" "create deployment")

  assert_not_empty "$ensure" "ensure service account index"
  assert_not_empty "$route" "route traffic index"
  assert_not_empty "$create" "create deployment index"
  assert_less_than "$ensure" "$route" "ensure service account index"
  assert_less_than "$route" "$create" "route traffic index"
}

@test "initial: ensure service account builds only the per-scope service account" {
  run yq -r '.steps[] | select(.name == "ensure service account") | .steps[0] | [.name, .file, .configuration.ACTION, .configuration.SERVICE_ACCOUNT_MODE, (.trace | tostring)] | join("|")' "$INITIAL"

  assert_equal "$status" "0"
  assert_equal "$output" "build service account|\$SERVICE_PATH/scope/iam/build_service_account|create|per-scope-only|false"
}

@test "initial: ensure service account applies the rendered manifest as a traced setting-up step" {
  run yq -r '.steps[] | select(.name == "ensure service account") | .steps[1] | [.name, .file, .configuration.ACTION, (.configuration.DRY_RUN | tostring), (.configuration.SKIP_WHEN_EMPTY | tostring), .trace.key, .trace.group] | join("|")' "$INITIAL"

  assert_equal "$status" "0"
  assert_equal "$output" "apply service account|\$SERVICE_PATH/apply_templates|apply|false|true|apply-service-account|setting-up"
}

@test "initial: inner step names do not collide with names overlays anchor on" {
  for name in "apply" "create deployment" "route traffic"; do
    count=$(yq -r "[.. | select(tag == \"!!map\") | select(.name == \"$name\")] | length" "$INITIAL")
    assert_equal "$count" "1" "occurrences of '$name'"
  done
}

@test "blue_green: inherits ensure service account from initial without overriding it" {
  run yq -r '.include[]' "$PROJECT_ROOT/k8s/deployment/workflows/blue_green.yaml"
  assert_contains "$output" "deployment/workflows/initial.yaml"

  run grep -E 'name: (ensure|build|apply) service account' "$PROJECT_ROOT/k8s/deployment/workflows/blue_green.yaml"
  assert_equal "$status" "1"
}

@test "scheduled_task overlays do not override the ensure service account steps" {
  run grep -rE 'name: (ensure|build|apply) service account' "$PROJECT_ROOT/scheduled_task/deployment/workflows"
  assert_equal "$status" "1"
}

@test "scope delete removes the service account rendered by build_service_account" {
  wf="$PROJECT_ROOT/k8s/scope/workflows/delete.yaml"
  run yq -r '.steps[] | select(.name == "iam") | .steps[] | .name + "|" + (.configuration.ACTION // "")' "$wf"

  assert_equal "$status" "0"
  assert_contains "$output" "build service account|delete"
  assert_contains "$output" "apply|delete"
}

@test "only the deployment ensure step opts in to SKIP_WHEN_EMPTY" {
  run grep -rl "SKIP_WHEN_EMPTY" "$PROJECT_ROOT/k8s" "$PROJECT_ROOT/scheduled_task" --include='*.yaml'
  assert_equal "$output" "$INITIAL"
}

# =============================================================================
# STRICT_PLACEHOLDERS: only the workflows that render pod specs fail on an
# unresolved placeholder; every other action stays tolerant.
# =============================================================================
build_context_strict() {
  yq -r '.steps[] | select(.name == "build context") | (.configuration.STRICT_PLACEHOLDERS // "unset") | tostring' "$1"
}

@test "STRICT_PLACEHOLDERS is set on the build context of scope create and deployment initial" {
  assert_equal "$(build_context_strict "$PROJECT_ROOT/k8s/scope/workflows/create.yaml")" "true"
  assert_equal "$(build_context_strict "$INITIAL")" "true"
}

@test "STRICT_PLACEHOLDERS is not set on non-rendering workflows" {
  for wf in k8s/scope/workflows/delete.yaml k8s/deployment/workflows/delete.yaml \
            k8s/deployment/workflows/rollback.yaml k8s/deployment/workflows/switch_traffic.yaml \
            k8s/deployment/workflows/finalize.yaml; do
    assert_equal "$(build_context_strict "$PROJECT_ROOT/$wf")" "unset" "$wf"
  done
  run bash -c "grep -rl STRICT_PLACEHOLDERS '$PROJECT_ROOT/k8s' '$PROJECT_ROOT/scheduled_task' --include='*.yaml' | sort"
  assert_equal "$output" "$(printf '%s\n%s' "$INITIAL" "$PROJECT_ROOT/k8s/scope/workflows/create.yaml" | sort)"
}

@test "scope update, blue_green and scheduled_task inherit the strict build context unchanged" {
  run yq -r '.include[]' "$PROJECT_ROOT/k8s/scope/workflows/update.yaml"
  assert_contains "$output" "scope/workflows/create.yaml"
  run grep -rE 'name: build context' "$PROJECT_ROOT/k8s/scope/workflows/update.yaml" \
    "$PROJECT_ROOT/k8s/deployment/workflows/blue_green.yaml" "$PROJECT_ROOT/scheduled_task"
  assert_equal "$status" "1"
}
