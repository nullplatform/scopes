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
# kill instances
#
# scheduled_task job pods are owned by Job -> CronJob, so the base k8s kill
# script (which reasons about Deployment/ReplicaSet ownership) is replaced by a
# job-aware script. The base must keep the step name so the overlay keeps
# matching it after upstream changes.
# =============================================================================
@test "base k8s deployment kill_instances workflow declares 'kill instances' step" {
  run grep -A 2 "name: kill instances" "$PROJECT_ROOT/k8s/deployment/workflows/kill_instances.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "type: script"
  assert_contains "$output" "deployment/kill_instances"
}

@test "scheduled_task deployment kill_instances overlay replaces 'kill instances' with its own script" {
  run grep -A 3 "name: kill instances" "$PROJECT_ROOT/scheduled_task/deployment/workflows/kill_instances.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "action: replace"
  assert_contains "$output" "\$OVERRIDES_PATH/deployment/kill_instances"
}

@test "base k8s deployment kill_instances workflow declares 'load logging' step" {
  run grep -A 2 "name: load logging" "$PROJECT_ROOT/k8s/deployment/workflows/kill_instances.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "type: script"
  assert_contains "$output" "logging"
}

@test "scheduled_task deployment kill_instances overlay loads its own logging function" {
  run grep -A 3 "name: load logging" "$PROJECT_ROOT/scheduled_task/deployment/workflows/kill_instances.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "action: replace"
  assert_contains "$output" "\$OVERRIDES_PATH/logging"
}
