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
      echo '{"status":"running"}'
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

mock_np_with_status() {
  np() {
    if [[ "$1 $2" == "deployment read" ]]; then
      [ "${NP_DEPLOYMENT_READ_FAILS:-false}" = "true" ] && { echo "Error connecting to API" >&2; return 1; }
      jq -cn --arg s "$NP_DEPLOYMENT_STATUS" '{status: (if $s == "null" then null else $s end)}'
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
    if [[ "$1 $2" == "deployment read" ]]; then echo "np $*" > "$BATS_TEST_TMPDIR/read.args"; echo '{"status":"running"}'; return 0; fi
    echo "WORKFLOW RAN: np $*"
  }
  export -f np
  export SERVICE_ACTION="start-blue-green" NP_API_KEY="secret"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  assert_contains "$output" "WORKFLOW RAN"
  [[ "$(cat "$BATS_TEST_TMPDIR/read.args")" != *"--api-key"* ]]
  assert_contains "$(cat "$BATS_TEST_TMPDIR/read.args")" "--format json"
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

# =============================================================================
# Deployment lock (k8s/deployment/deployment_lock)
# =============================================================================

setup_lock() {
  export SERVICE_PATH="$BATS_TEST_TMPDIR/service-path"
  mkdir -p "$SERVICE_PATH/deployment/workflows"
  cp "$PROJECT_ROOT/k8s/deployment/deployment_lock" "$PROJECT_ROOT/k8s/deployment/wait_deployment_lock" "$PROJECT_ROOT/k8s/deployment/deployment_status" "$SERVICE_PATH/deployment/"
  cp "$PROJECT_ROOT/k8s/deployment/workflows/"*.yaml "$SERVICE_PATH/deployment/workflows/"
  export SCOPE_ID="scope-123" K8S_NAMESPACE="test-namespace"
  export LEASE_FILE="$BATS_TEST_TMPDIR/lease.json" STATUS_FILE="$BATS_TEST_TMPDIR/deployment.status"
  export NP_DEPLOYMENT_STATUS="running" NP_DEPLOY_LOCK_POLL_SECONDS=1 NP_DEPLOY_LOCK_WAIT_TIMEOUT=30
  log() { echo "$2"; }
  export -f log

  kubectl() {
    local cur new
    echo "$*" >> "$BATS_TEST_TMPDIR/kubectl.calls"
    case "$1" in
      get) [ -f "$LEASE_FILE" ] || return 1; cat "$LEASE_FILE" ;;
      create)
        [ "${KUBECTL_FORBIDDEN:-false}" = "true" ] && return 1
        [ -f "$LEASE_FILE" ] && return 1
        jq '.metadata.resourceVersion = "1"' > "$LEASE_FILE" ;;
      replace)
        new=$(cat); cur=$(jq -r '.metadata.resourceVersion' "$LEASE_FILE")
        [ "$(jq -r '.metadata.resourceVersion' <<<"$new")" = "$cur" ] || return 1
        jq --arg rv "$((cur + 1))" '.metadata.resourceVersion = $rv' <<<"$new" > "$LEASE_FILE.tmp" && mv "$LEASE_FILE.tmp" "$LEASE_FILE" ;;
      patch) return 0 ;;
    esac
  }
  export -f kubectl

  np() {
    if [[ "$1 $2" == "deployment read" ]]; then
      jq -cn --arg s "$(if [ -f "$STATUS_FILE" ]; then cat "$STATUS_FILE"; else echo "$NP_DEPLOYMENT_STATUS"; fi)" '{status: $s}'
      return 0
    fi
    if [[ "$*" == *"--help"* ]]; then return 0; fi
    if [[ "$*" == *"lock_wait.yaml"* ]]; then K8S_NAMESPACE=nullplatform bash "$SERVICE_PATH/deployment/wait_deployment_lock"; return $?; fi
    echo "WORKFLOW RAN: np $*"
    return "${NP_WORKFLOW_RC:-0}"
  }
  export -f np
}

lease_held_then_released() {
  jq -n --arg renew "$(date -u +%s)" '{
    apiVersion: "coordination.k8s.io/v1", kind: "Lease",
    metadata: {name: "np-deploy-lock-scope-123", namespace: "test-namespace", resourceVersion: "3",
               annotations: {"nullplatform.com/action": "start-blue-green", "nullplatform.com/deployment-id": "deploy-456",
                             "nullplatform.com/renew-epoch": $renew}},
    spec: {holderIdentity: "holder-b", leaseDurationSeconds: 60}}' > "$LEASE_FILE"
  ( sleep "$1"
    [ -n "${2:-}" ] && echo "$2" > "$STATUS_FILE"
    jq 'del(.spec.holderIdentity) | .metadata.resourceVersion = "4"' "$LEASE_FILE" > "$LEASE_FILE.tmp" &&
      mv "$LEASE_FILE.tmp" "$LEASE_FILE" ) &
}

@test "deployment entrypoint: with the lock free the action runs and releases it" {
  setup_lock
  export SERVICE_ACTION="start-blue-green"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "WORKFLOW RAN"
  [ "$(jq -r '.spec.holderIdentity // ""' "$LEASE_FILE")" = "" ]
}

@test "deployment entrypoint: a failed action still releases the lock" {
  setup_lock
  export SERVICE_ACTION="switch-traffic" NP_WORKFLOW_RC=1

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 1 ]
  [ "$(jq -r '.spec.holderIdentity // ""' "$LEASE_FILE")" = "" ]
}

@test "deployment entrypoint: a duplicate waits for the original and ends without running when the deployment moved past it" {
  setup_lock
  export SERVICE_ACTION="finalize-blue-green"
  lease_held_then_released 2 "finalized"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "waiting for it to finish"
  assert_contains "$output" "lock_wait.yaml"
  assert_contains "$output" "--no-output"
  assert_contains "$output" "already 'finalized': action finalize-blue-green was already applied"
  [[ "$output" != *"WORKFLOW RAN"* ]]
}

@test "deployment entrypoint: a duplicate waits for the original and runs again when the status does not show it applied" {
  setup_lock
  export SERVICE_ACTION="start-blue-green"
  lease_held_then_released 2 "running"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "waiting for it to finish"
  assert_contains "$output" "WORKFLOW RAN"
}

@test "deployment entrypoint: the wait looks at the entrypoint's lease even if the workflow resets K8S_NAMESPACE" {
  setup_lock
  export SERVICE_ACTION="start-blue-green"
  lease_held_then_released 2

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Lock acquired"
  ! grep -q -- "-n nullplatform" "$BATS_TEST_TMPDIR/kubectl.calls"
}

@test "deployment entrypoint: the next action waits for the running one, then runs" {
  setup_lock
  export SERVICE_ACTION="switch-traffic"
  lease_held_then_released 2

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "waiting for it to finish"
  assert_contains "$output" "WORKFLOW RAN"
}

@test "deployment entrypoint: when the lock cannot be used the action runs without it" {
  setup_lock
  export SERVICE_ACTION="start-blue-green" KUBECTL_FORBIDDEN=true

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Deployment lock not available on scope scope-123: running without it"
  assert_contains "$output" "WORKFLOW RAN"
}

@test "deployment entrypoint: actions that do not change the scope never touch the lock" {
  setup_lock
  export SERVICE_ACTION="diagnose-deployment"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  assert_contains "$output" "WORKFLOW RAN"
  [ ! -f "$LEASE_FILE" ]
}
