#!/usr/bin/env bats
# =============================================================================
# Tests that verify scheduled_task deployment workflows override base k8s steps
# that do not apply to this scope type (e.g. ALB target group capacity).
#
# Contract:
#   - Overlay must mark the step with `action: skip`.
#   - Base workflow must still declare the step under the same name, otherwise
#     a rename upstream would silently re-enable the step here.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export OVERLAY="$PROJECT_ROOT/scheduled_task/deployment/workflows/initial.yaml"
  export BASE="$PROJECT_ROOT/k8s/deployment/workflows/initial.yaml"
}

# =============================================================================
# validate alb target group capacity
# =============================================================================
@test "base k8s deployment initial workflow declares 'validate alb target group capacity' step" {
  run grep -A 2 "name: validate alb target group capacity" "$BASE"

  assert_equal "$status" "0"
  assert_contains "$output" "type: script"
  assert_contains "$output" "validate_alb_target_group_capacity"
}

@test "scheduled_task deployment initial overlay skips 'validate alb target group capacity'" {
  run grep -A 1 "name: validate alb target group capacity" "$OVERLAY"

  assert_equal "$status" "0"
  assert_contains "$output" "action: skip"
}

# =============================================================================
# kill job execution
#
# scheduled_task pods are owned by Job -> CronJob, so this action ships a
# STANDALONE deployment workflow (not an override of a k8s base) with its own
# steps. The deployment entrypoint falls back to the override-provided workflow
# because k8s has no kill_job_execution counterpart.
# =============================================================================
@test "kill_job_execution has no base k8s workflow (it is standalone)" {
  run test -f "$PROJECT_ROOT/k8s/deployment/workflows/kill_job_execution.yaml"

  assert_equal "$status" "1"
}

@test "scheduled_task deployment kill_job_execution workflow loads its own logging function" {
  run grep -A 3 "name: load logging" "$PROJECT_ROOT/scheduled_task/deployment/workflows/kill_job_execution.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "type: script"
  assert_contains "$output" "\$OVERRIDES_PATH/logging"
}

@test "scheduled_task deployment kill_job_execution workflow runs its own kill script" {
  run grep -A 2 "name: kill job execution" "$PROJECT_ROOT/scheduled_task/deployment/workflows/kill_job_execution.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "type: script"
  assert_contains "$output" "\$OVERRIDES_PATH/deployment/kill_job_execution"
}

@test "scheduled_task deployment kill_job_execution workflow is not an override (no action: replace)" {
  run grep -c "action: replace" "$PROJECT_ROOT/scheduled_task/deployment/workflows/kill_job_execution.yaml"

  assert_contains "$output" "0"
}
