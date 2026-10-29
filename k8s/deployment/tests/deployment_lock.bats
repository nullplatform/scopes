#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { echo "$2"; }
  export -f log

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-456"
  export SERVICE_ACTION="start-blue-green"
  export K8S_NAMESPACE="test-namespace"
  export NP_DEPLOY_LOCK_HOLDER="holder-a"
  export LEASE_FILE="$BATS_TEST_TMPDIR/lease.json"

  kubectl() {
    local verb="$1" cur new
    case "$verb" in
      get)
        [ -f "$LEASE_FILE" ] || return 1
        cat "$LEASE_FILE"
        ;;
      create)
        [ "${KUBECTL_FORBIDDEN:-false}" = "true" ] && { echo "forbidden" >&2; return 1; }
        [ -f "$LEASE_FILE" ] && { echo "AlreadyExists" >&2; return 1; }
        jq '.metadata.resourceVersion = "1"' > "$LEASE_FILE"
        ;;
      replace)
        new=$(cat)
        cur=$(jq -r '.metadata.resourceVersion' "$LEASE_FILE")
        [ "$(jq -r '.metadata.resourceVersion' <<<"$new")" = "$cur" ] || { echo "conflict" >&2; return 1; }
        jq --arg rv "$((cur + 1))" '.metadata.resourceVersion = $rv' <<<"$new" > "$LEASE_FILE.tmp" && mv "$LEASE_FILE.tmp" "$LEASE_FILE"
        ;;
      patch)
        local p="" prev=""
        for a in "$@"; do [ "$prev" = "-p" ] && p="$a"; prev="$a"; done
        cur=$(jq -r '.metadata.resourceVersion' "$LEASE_FILE")
        jq --argjson p "$p" --arg rv "$((cur + 1))" '. * $p | .metadata.resourceVersion = $rv' "$LEASE_FILE" > "$LEASE_FILE.tmp" && mv "$LEASE_FILE.tmp" "$LEASE_FILE"
        ;;
    esac
  }
  export -f kubectl

  source "$SERVICE_PATH/deployment/deployment_lock"
}

lease_held_by() {
  jq -n --arg h "$1" --arg renew "$(( $(date -u +%s) - $2 ))" '{
    apiVersion: "coordination.k8s.io/v1", kind: "Lease",
    metadata: {name: "np-deploy-lock-scope-123", namespace: "test-namespace", resourceVersion: "7",
               annotations: {"nullplatform.com/action": "switch-traffic", "nullplatform.com/deployment-id": "deploy-111",
                             "nullplatform.com/renew-epoch": $renew}},
    spec: {holderIdentity: $h, leaseDurationSeconds: 60}}' > "$LEASE_FILE"
}

@test "deployment_lock: the first execution creates the lease and holds it" {
  run deployment_lock_try_acquire
  [ "$status" -eq 0 ]
  assert_equal "$(jq -r '.spec.holderIdentity' "$LEASE_FILE")" "holder-a"
  assert_equal "$(jq -r '.metadata.name' "$LEASE_FILE")" "np-deploy-lock-scope-123"
  assert_equal "$(jq -r '.metadata.namespace' "$LEASE_FILE")" "test-namespace"
  assert_equal "$(jq -r '.metadata.annotations["nullplatform.com/action"]' "$LEASE_FILE")" "start-blue-green"
  deployment_lock_held
}

@test "deployment_lock: a lease renewed recently by another execution is busy" {
  lease_held_by "holder-b" 5

  run deployment_lock_try_acquire

  [ "$status" -eq 1 ]
  assert_equal "$(jq -r '.spec.holderIdentity' "$LEASE_FILE")" "holder-b"
  assert_equal "$(deployment_lock_holder_summary)" "switch-traffic of deployment deploy-111"
}

@test "deployment_lock: an expired lease is taken over" {
  lease_held_by "holder-dead" 120

  run deployment_lock_try_acquire

  [ "$status" -eq 0 ]
  assert_equal "$(jq -r '.spec.holderIdentity' "$LEASE_FILE")" "holder-a"
  assert_equal "$(jq -r '.metadata.annotations["nullplatform.com/action"]' "$LEASE_FILE")" "start-blue-green"
}

@test "deployment_lock: a lease taken by someone else between read and write is not stolen" {
  lease_held_by "" 0
  _dl_get() { cat "$LEASE_FILE"; jq '.metadata.resourceVersion = "8" | .spec.holderIdentity = "holder-b"' "$LEASE_FILE" > "$LEASE_FILE.tmp"; mv "$LEASE_FILE.tmp" "$LEASE_FILE"; }

  run deployment_lock_try_acquire

  [ "$status" -eq 1 ]
  assert_equal "$(jq -r '.spec.holderIdentity' "$LEASE_FILE")" "holder-b"
}

@test "deployment_lock: release frees the lock for the next execution" {
  deployment_lock_try_acquire

  deployment_lock_release

  assert_equal "$(jq -r '.spec.holderIdentity // ""' "$LEASE_FILE")" ""
  NP_DEPLOY_LOCK_HOLDER="holder-b" run deployment_lock_try_acquire
  [ "$status" -eq 0 ]
}

@test "deployment_lock: release by an execution that does not hold it changes nothing" {
  lease_held_by "holder-b" 5
  before=$(cat "$LEASE_FILE")

  deployment_lock_release

  assert_equal "$(cat "$LEASE_FILE")" "$before"
}

@test "deployment_lock: without permission on leases the lock is reported unusable" {
  export KUBECTL_FORBIDDEN=true

  run deployment_lock_try_acquire

  [ "$status" -eq 2 ]
}

@test "deployment_lock: only actions that change the scope take it" {
  for action in start-initial start-blue-green switch-traffic rollback-deployment finalize-blue-green delete-deployment; do
    deployment_lock_applies "$action"
  done
  for action in diagnose-deployment kill-instance; do
    ! deployment_lock_applies "$action"
  done
}

@test "wait_deployment_lock: takes the lock once the running action releases it" {
  lease_held_by "holder-b" 0
  export NP_DEPLOY_LOCK_POLL_SECONDS=1 NP_DEPLOY_LOCK_WAIT_TIMEOUT=30
  ( sleep 2; NP_DEPLOY_LOCK_HOLDER="holder-b" SERVICE_ACTION="switch-traffic" DEPLOYMENT_ID="deploy-111" deployment_lock_release ) &

  run bash "$SERVICE_PATH/deployment/wait_deployment_lock"

  [ "$status" -eq 0 ]
  assert_contains "$output" "waiting for it to finish"
  assert_contains "$output" "Lock acquired"
  assert_equal "$(jq -r '.spec.holderIdentity' "$LEASE_FILE")" "holder-a"
}

@test "wait_deployment_lock: gives up after the timeout" {
  lease_held_by "holder-b" 0
  ( for _ in 1 2 3 4; do sleep 1; jq --arg r "$(date -u +%s)" '.metadata.annotations["nullplatform.com/renew-epoch"] = $r' "$LEASE_FILE" > "$LEASE_FILE.r" && mv "$LEASE_FILE.r" "$LEASE_FILE"; done ) &
  export NP_DEPLOY_LOCK_POLL_SECONDS=1 NP_DEPLOY_LOCK_WAIT_TIMEOUT=2

  run bash "$SERVICE_PATH/deployment/wait_deployment_lock"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Gave up after 2s waiting for switch-traffic of deployment deploy-111"
}
