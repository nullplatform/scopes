#!/usr/bin/env bats
# =============================================================================
# Unit tests for service/deployment/entrypoint - --no-params flag behavior
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-456"
  export SERVICE_PATH="/tmp/test-service-path"
  export OVERRIDES_PATH=""

  mkdir -p "$SERVICE_PATH/deployment/workflows"
  touch "$SERVICE_PATH/deployment/workflows/initial.yaml"
  touch "$SERVICE_PATH/deployment/workflows/blue_green.yaml"
  touch "$SERVICE_PATH/deployment/workflows/switch_traffic.yaml"
  touch "$SERVICE_PATH/deployment/workflows/rollback.yaml"
  touch "$SERVICE_PATH/deployment/workflows/finalize.yaml"
  touch "$SERVICE_PATH/deployment/workflows/delete.yaml"
  touch "$SERVICE_PATH/deployment/workflows/diagnose.yaml"
  touch "$SERVICE_PATH/deployment/workflows/kill_instance.yaml"
  cp "$PROJECT_ROOT/k8s/deployment/deployment_status" "$SERVICE_PATH/deployment/"
  export DEPLOYMENT_STATUS_READ_RETRY_SECONDS=0

  export NP_EXECUTED_CMD=""
  export NP_HELP_SUPPORTS_NO_PARAMS="true"
}

teardown() {
  rm -rf "$SERVICE_PATH"
  unset -f np
}

mock_np() {
  np() {
    if [[ "$1 $2" == "deployment read" ]]; then
      echo "running"
      return 0
    fi
    if [[ "$*" == *"--help"* ]]; then
      if [ "$NP_HELP_SUPPORTS_NO_PARAMS" = "true" ]; then
        echo "  --no-params    Skip parameter fetching"
      fi
      return 0
    fi
    export NP_EXECUTED_CMD="np $*"
    return 0
  }
  export -f np
}

# =============================================================================
# Actions that SHOULD include --no-params (when CLI supports it)
# =============================================================================

@test "deployment entrypoint: switch-traffic includes --no-params when CLI supports it" {
  mock_np
  export SERVICE_ACTION="switch-traffic"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

@test "deployment entrypoint: kill-instance includes --no-params when CLI supports it" {
  mock_np
  export SERVICE_ACTION="kill-instance"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

@test "deployment entrypoint: diagnose-deployment includes --no-params when CLI supports it" {
  mock_np
  export SERVICE_ACTION="diagnose-deployment"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

# =============================================================================
# Actions that SHOULD NOT include --no-params
# =============================================================================

@test "deployment entrypoint: start-initial does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="start-initial"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: start-blue-green does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="start-blue-green"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: rollback-deployment does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="rollback-deployment"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: finalize-blue-green does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="finalize-blue-green"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: delete-deployment does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="delete-deployment"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

# =============================================================================
# Backward compatibility - old CLI without --no-params support
# =============================================================================

@test "deployment entrypoint: switch-traffic omits --no-params when CLI does not support it" {
  export NP_HELP_SUPPORTS_NO_PARAMS="false"
  mock_np
  export SERVICE_ACTION="switch-traffic"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: kill-instance omits --no-params when CLI does not support it" {
  export NP_HELP_SUPPORTS_NO_PARAMS="false"
  mock_np
  export SERVICE_ACTION="kill-instance"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

# =============================================================================
# Edge cases
# =============================================================================

@test "deployment entrypoint: unknown action fails" {
  mock_np
  export SERVICE_ACTION="unknown-action"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Unknown action"
}

@test "deployment entrypoint: --build-context and --include-secrets always present" {
  mock_np
  export SERVICE_ACTION="switch-traffic"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--build-context"
  assert_contains "$output" "--include-secrets"
}

# =============================================================================
# Re-delivered or late actions: deployment already past this action
# =============================================================================

# np mock: `deployment read` answers $NP_DEPLOYMENT_STATUS (or fails when
# $NP_DEPLOYMENT_READ_FAILS is true); the workflow command echoes a marker so
# tests can tell whether it ran.
mock_np_with_status() {
  np() {
    if [[ "$1 $2" == "deployment read" ]]; then
      [ "${NP_DEPLOYMENT_READ_FAILS:-false}" = "true" ] && { echo "Error connecting to API" >&2; return 1; }
      echo "$NP_DEPLOYMENT_STATUS"
      return 0
    fi
    if [[ "$*" == *"--help"* ]]; then
      return 0
    fi
    echo "WORKFLOW RAN: np $*"
  }
  export -f np
}

@test "deployment entrypoint: late finalize-blue-green on a finalized deployment succeeds without running the workflow" {
  mock_np_with_status
  export SERVICE_ACTION="finalize-blue-green" NP_DEPLOYMENT_STATUS="finalized"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "already 'finalized': action finalize-blue-green was already applied"
  [[ "$output" != *"WORKFLOW RAN"* ]]
}

@test "deployment entrypoint: re-delivered start-blue-green on a finalizing deployment is skipped" {
  mock_np_with_status
  export SERVICE_ACTION="start-blue-green" NP_DEPLOYMENT_STATUS="finalizing"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"WORKFLOW RAN"* ]]
}

@test "deployment entrypoint: each action is skipped only on the statuses it leads to" {
  mock_np_with_status
  for pair in "start-initial finalized" "switch-traffic finalizing" "switch-traffic finalized" \
              "rollback-deployment rolled_back" "rollback-deployment cancelled" "delete-deployment deleted"; do
    export SERVICE_ACTION="${pair% *}" NP_DEPLOYMENT_STATUS="${pair#* }"
    run bash "$BATS_TEST_DIRNAME/../entrypoint"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WORKFLOW RAN"* ]] || { echo "workflow ran for $pair"; return 1; }
  done
}

@test "deployment entrypoint: the workflow runs when the status is the expected or an incompatible one" {
  mock_np_with_status
  for pair in "finalize-blue-green finalizing" "start-blue-green running" "start-blue-green failed" \
              "switch-traffic running" "rollback-deployment rolling_back" "delete-deployment deleting" \
              "finalize-blue-green rolled_back"; do
    export SERVICE_ACTION="${pair% *}" NP_DEPLOYMENT_STATUS="${pair#* }"
    run bash "$BATS_TEST_DIRNAME/../entrypoint"
    assert_contains "$output" "WORKFLOW RAN"
  done
}

@test "deployment entrypoint: a status read that keeps failing fails the action without running the workflow" {
  mock_np_with_status
  export SERVICE_ACTION="finalize-blue-green" NP_DEPLOYMENT_READ_FAILS="true"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not read the status of deployment deploy-456"
  [[ "$output" != *"WORKFLOW RAN"* ]]
}

@test "deployment entrypoint: a response without a status fails the action without running the workflow" {
  mock_np_with_status
  export SERVICE_ACTION="start-blue-green" NP_DEPLOYMENT_STATUS="null"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 1 ]
  assert_contains "$output" "no status in the response"
  [[ "$output" != *"WORKFLOW RAN"* ]]
}

@test "deployment entrypoint: the status is read without passing the api key" {
  np() {
    if [[ "$1 $2" == "deployment read" ]]; then echo "np $*" > "$BATS_TEST_TMPDIR/read.args"; echo "running"; return 0; fi
    echo "WORKFLOW RAN: np $*"
  }
  export -f np
  export SERVICE_ACTION="start-blue-green" NP_API_KEY="secret"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  assert_contains "$output" "WORKFLOW RAN"
  [[ "$(cat "$BATS_TEST_TMPDIR/read.args")" != *"--api-key"* ]]
}

@test "deployment entrypoint: actions without a final status never read it" {
  np() {
    if [[ "$1 $2" == "deployment read" ]]; then
      echo "UNEXPECTED STATUS READ"
      return 0
    fi
    echo "WORKFLOW RAN: np $*"
  }
  export -f np
  for action in diagnose-deployment kill-instance; do
    export SERVICE_ACTION="$action"
    run bash "$BATS_TEST_DIRNAME/../entrypoint"
    assert_contains "$output" "WORKFLOW RAN"
    [[ "$output" != *"UNEXPECTED STATUS READ"* ]]
  done
}
