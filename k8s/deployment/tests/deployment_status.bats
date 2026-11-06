#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export DEPLOYMENT_ID="deploy-456"
  export DEPLOYMENT_STATUS_READ_RETRY_SECONDS=0
  export CALLS_FILE="$BATS_TEST_TMPDIR/np.calls"
  source "$PROJECT_ROOT/k8s/deployment/deployment_status"
}

@test "deployment_status_read: leaves the status in DEPLOYMENT_STATUS" {
  np() { echo "np $*" >> "$CALLS_FILE"; echo '{"id":"deploy-456","status":"running"}'; }

  rc=0
  deployment_status_read || rc=$?

  assert_equal "$rc" "$DS_OK"
  assert_equal "$DEPLOYMENT_STATUS" "running"
  assert_equal "$DEPLOYMENT_STATUS_ERROR" ""
  assert_equal "$(cat "$CALLS_FILE")" "np deployment read --id deploy-456 --format json"
}

@test "deployment_status_read: text printed by the CLI around the response is never taken as the status" {
  np() { echo "A new version of np is available"; echo '{"status":"finalized"}'; }

  rc=0
  deployment_status_read || rc=$?

  assert_equal "$rc" "$DS_NO_STATUS"
  assert_equal "$DEPLOYMENT_STATUS" ""
}

@test "deployment_status_read: retries a failed read" {
  np() {
    echo x >> "$CALLS_FILE"
    [ "$(wc -l < "$CALLS_FILE")" -ge 2 ] && { echo '{"status":"finalized"}'; return 0; }
    echo "Error connecting to API"; return 1
  }

  rc=0
  deployment_status_read || rc=$?

  assert_equal "$rc" "$DS_OK"
  assert_equal "$DEPLOYMENT_STATUS" "finalized"
}

@test "deployment_status_read: a CLI that keeps failing returns DS_CLI_ERROR with its message" {
  np() { echo x >> "$CALLS_FILE"; echo "error: request failed with status 500"; return 1; }

  rc=0
  deployment_status_read || rc=$?

  assert_equal "$rc" "$DS_CLI_ERROR"
  assert_equal "$DEPLOYMENT_STATUS" ""
  assert_contains "$DEPLOYMENT_STATUS_ERROR" "request failed with status 500"
  assert_equal "$(wc -l < "$CALLS_FILE" | tr -d ' ')" "3"
}

@test "deployment_status_read: a CLI error reported as JSON keeps only its message" {
  np() { echo '{"error":"request failed with status 403: Insufficient permission"}'; return 1; }

  rc=0
  deployment_status_read || rc=$?

  assert_equal "$rc" "$DS_CLI_ERROR"
  assert_equal "$DEPLOYMENT_STATUS_ERROR" "request failed with status 403: Insufficient permission"
}

@test "deployment_status_read: a response without a status returns DS_NO_STATUS" {
  for answer in '{"status":null}' '{"status":""}' '{}' '' 'running'; do
    np() { echo "$answer"; }

    rc=0
    deployment_status_read || rc=$?

    [ "$rc" -eq "$DS_NO_STATUS" ] || { echo "answer '$answer' returned $rc"; return 1; }
    assert_equal "$DEPLOYMENT_STATUS" ""
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
