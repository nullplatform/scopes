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
