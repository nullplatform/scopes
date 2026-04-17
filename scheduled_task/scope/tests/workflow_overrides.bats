#!/usr/bin/env bats
# =============================================================================
# Tests that verify scheduled_task scope workflows override base k8s steps
# that do not apply to this scope type (e.g. ALB capacity validation).
#
# Contract:
#   - Overlay must mark the step with `action: skip`.
#   - Base workflow must still declare the step under the same name, otherwise
#     the skip is a no-op and the base step would not run anyway (or worse, a
#     rename upstream would silently re-enable the step here).
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export OVERLAY="$PROJECT_ROOT/scheduled_task/scope/workflows/create.yaml"
  export BASE="$PROJECT_ROOT/k8s/scope/workflows/create.yaml"
}

# =============================================================================
# validate alb capacity
# =============================================================================
@test "base k8s scope create workflow declares 'validate alb capacity' step" {
  run grep -A 2 "name: validate alb capacity" "$BASE"

  assert_equal "$status" "0"
  assert_contains "$output" "type: script"
  assert_contains "$output" "validate_alb_capacity"
}

@test "scheduled_task scope create overlay skips 'validate alb capacity'" {
  run grep -A 1 "name: validate alb capacity" "$OVERLAY"

  assert_equal "$status" "0"
  assert_contains "$output" "action: skip"
}

# =============================================================================
# networking (scheduled_task has no public traffic, so the whole block is skipped)
# =============================================================================
@test "base k8s scope create workflow declares 'networking' step" {
  run grep -A 1 "name: networking" "$BASE"

  assert_equal "$status" "0"
  assert_contains "$output" "type: workflow"
}

@test "scheduled_task scope create overlay skips 'networking'" {
  run grep -A 1 "name: networking" "$OVERLAY"

  assert_equal "$status" "0"
  assert_contains "$output" "action: skip"
}
