#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/deployment_status
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export DEPLOYMENT_ID="deploy-456"
  export DEPLOYMENT_STATUS_READ_RETRY_SECONDS=0
  export CALLS_FILE="$BATS_TEST_TMPDIR/np.calls"
  source "$PROJECT_ROOT/k8s/deployment/deployment_status"
}

@test "deployment_status_read: prints the status" {
  np() { echo "np $*" >> "$CALLS_FILE"; echo "running"; }

  run deployment_status_read

  [ "$status" -eq 0 ]
  assert_equal "$output" "running"
  assert_equal "$(cat "$CALLS_FILE")" "np deployment read --id deploy-456 --query .status"
}

@test "deployment_status_read: retries a failed read" {
  np() {
    echo x >> "$CALLS_FILE"
    [ "$(wc -l < "$CALLS_FILE")" -ge 2 ] && { echo "finalized"; return 0; }
    echo "Error connecting to API" >&2; return 1
  }

  run deployment_status_read

  [ "$status" -eq 0 ]
  assert_equal "$output" "finalized"
}

@test "deployment_status_read: returns 1 with the CLI error when every attempt fails" {
  np() { echo x >> "$CALLS_FILE"; echo "Error connecting to API" >&2; return 1; }

  run deployment_status_read

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error connecting to API"
  assert_equal "$(wc -l < "$CALLS_FILE" | tr -d ' ')" "3"
}

@test "deployment_status_read: returns 2 when the response has no status" {
  for answer in "" "null"; do
    np() { echo "$answer"; }
    run deployment_status_read
    [ "$status" -eq 2 ] || { echo "answer '$answer' returned $status"; return 1; }
  done
}

@test "deployment_action_already_applied: each action only on the statuses it leads to" {
  for pair in "start-initial finalizing" "start-blue-green finalized" "switch-traffic finalizing" \
              "finalize-blue-green finalized" "rollback-deployment rolled_back" "rollback-deployment cancelled" \
              "delete-deployment deleted"; do
    deployment_action_already_applied ${pair} || { echo "expected applied: $pair"; return 1; }
  done
  for pair in "start-blue-green running" "start-blue-green failed" "finalize-blue-green finalizing" \
              "rollback-deployment rolling_back" "delete-deployment deleting" "diagnose-deployment finalized" \
              "kill-instance deleted"; do
    ! deployment_action_already_applied ${pair} || { echo "expected not applied: $pair"; return 1; }
  done
}
