#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/networking/gateway/service_to_service_gateway_move
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  for helper in np_scope_step_begin np_scope_step_end; do
    eval "$helper() { :; }"
    export -f "$helper"
  done
  sleep() { :; }
  export -f sleep

  export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  export LIVE_HOST="gateway-private-istio.gateways.svc.cluster.local"
  export ROUTES_FILE="$BATS_TEST_TMPDIR/routes.json"
  export ACCEPTED_FILE="$BATS_TEST_TMPDIR/accepted"
  unset SERVICE_TO_SERVICE_KEEP_PREVIOUS

  export CONTEXT='{
    "k8s_namespace": "apps",
    "scope": {"id": 123},
    "names": {"stable_service": "checkout"},
    "service_to_service": {"enabled": true, "gateway_name": "gateway-in-cluster", "gateway_namespace": "gateways",
      "gateway_host": "gateway-in-cluster-istio.gateways.svc.cluster.local", "ports": [8080, 9090], "grpc_ports": [9090]}
  }'

  # Live routes attached to the private gateway (accepted) and to a gateway that rejected them.
  cat > "$ROUTES_FILE" <<'JSON'
{"items": [
  {"metadata": {"name": "checkout-http-8080"}, "status": {"parents": [
    {"parentRef": {"name": "gateway-private", "namespace": "gateways", "sectionName": "in-cluster-8080"},
     "conditions": [{"type": "Accepted", "status": "True"}]},
    {"parentRef": {"name": "gateway-in-cluster", "namespace": "gateways", "sectionName": "in-cluster-8080"},
     "conditions": [{"type": "Accepted", "status": "True"}]},
    {"parentRef": {"name": "gateway-old", "namespace": "gateways", "sectionName": "in-cluster-8080"},
     "conditions": [{"type": "Accepted", "status": "False"}]}]}},
  {"metadata": {"name": "checkout-grpc-9090"}, "status": {"parents": [
    {"parentRef": {"name": "gateway-private", "sectionName": "in-cluster-9090"},
     "conditions": [{"type": "Accepted", "status": "True"}]}]}},
  {"metadata": {"name": "other-http-8080"}, "status": {"parents": [
    {"parentRef": {"name": "gateway-private", "namespace": "gateways"},
     "conditions": [{"type": "Accepted", "status": "True"}]}]}}
]}
JSON

  kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    case "$1 $2" in
      "get service") echo -n "$LIVE_HOST" ;;
      "get httproute")
        if [ "$3" = "-n" ]; then cat "$ROUTES_FILE"; return 0; fi
        if [ -f "$ACCEPTED_FILE" ]; then
          echo '{"status": {"parents": [{"parentRef": {"name": "gateway-in-cluster", "namespace": "gateways"}, "conditions": [{"type": "Accepted", "status": "True"}]}]}}'
        else
          echo '{"status": {"parents": []}}'
        fi ;;
      "patch service") echo "service/checkout patched" ;;
    esac
  }
  export -f kubectl
  source "$PROJECT_ROOT/k8s/deployment/networking/gateway/service_to_service_gateway_move"
}

@test "gateway move: while moving, keeps the ExternalName and every accepted parent of another gateway" {
  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -r .service_to_service.external_name)" "$LIVE_HOST"
  assert_equal "$(echo "$CONTEXT" | jq -c .service_to_service.previous_parents)" \
    '{"8080":[{"name":"gateway-private","namespace":"gateways","sectionName":"in-cluster-8080"}],"9090":[{"name":"gateway-private","namespace":"apps","sectionName":"in-cluster-9090"}]}'
}

@test "gateway move: not moving, drops the old parents (finalize, rollback, initial)" {
  export LIVE_HOST="gateway-in-cluster-istio.gateways.svc.cluster.local"

  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -c '.service_to_service | [has("external_name"), has("previous_parents")]')" '[false,false]'
}

@test "gateway move: not moving, keeps the old parents while blue still serves (blue-green start, switch)" {
  export LIVE_HOST="gateway-in-cluster-istio.gateways.svc.cluster.local"
  export SERVICE_TO_SERVICE_KEEP_PREVIOUS=true

  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -r 'has("external_name")')" "false"
  assert_equal "$(echo "$CONTEXT" | jq -r '.service_to_service.previous_parents | keys | join(",")')" "8080,9090"
}

@test "gateway move: nothing is read when the feature is off" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.service_to_service.enabled = false')

  service_to_service_previous_gateway

  [ ! -f "$KUBECTL_LOG" ]
}

@test "gateway move: an unreadable cluster renders the plain switch with a warning" {
  kubectl() { echo "Forbidden"; return 1; }
  export -f kubectl

  run service_to_service_previous_gateway

  [ "$status" -eq 0 ]
  assert_contains "$output" "Could not read the live service-to-service objects"
}

@test "gateway move: finish does nothing when the ExternalName already points at the gateway" {
  export LIVE_HOST="gateway-in-cluster-istio.gateways.svc.cluster.local"

  run service_to_service_finish_gateway_move

  [ "$status" -eq 0 ]
  [[ "$(cat "$KUBECTL_LOG")" != *"patch"* ]] || false
}

@test "gateway move: finish switches the ExternalName once the new gateway accepts every internal route" {
  touch "$ACCEPTED_FILE"

  run service_to_service_finish_gateway_move

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_LOG")" "get httproute checkout-http-8080 -n apps -o json"
  assert_contains "$(cat "$KUBECTL_LOG")" "get httproute checkout-grpc-9090 -n apps -o json"
  assert_contains "$(cat "$KUBECTL_LOG")" 'patch service checkout -n apps --type merge -p {"spec":{"externalName":"gateway-in-cluster-istio.gateways.svc.cluster.local"}}'
  assert_contains "$output" "✅ checkout now resolves to gateway-in-cluster-istio.gateways.svc.cluster.local"
}

@test "gateway move: finish keeps the old gateway when the new one never accepts the routes" {
  export SERVICE_TO_SERVICE_MOVE_TIMEOUT_SECONDS=4

  run service_to_service_finish_gateway_move

  [ "$status" -eq 0 ]
  [[ "$(cat "$KUBECTL_LOG")" != *"patch"* ]] || false
  assert_contains "$output" "has not accepted checkout-http-8080 checkout-grpc-9090 after 4s; checkout keeps pointing at $LIVE_HOST"
}
