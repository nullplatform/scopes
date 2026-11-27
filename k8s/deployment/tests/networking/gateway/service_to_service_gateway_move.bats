#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/networking/gateway/service_to_service_gateway_move
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  for helper in np_scope_step_begin np_scope_step_end np_scope_output; do
    eval "$helper() { :; }"
    export -f "$helper"
  done
  sleep() { :; }
  export -f sleep

  export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  export LIVE_HOST="gateway-private-istio.gateways.svc.cluster.local"
  export SAVED_HOSTNAMES=""
  export ROUTES_FILE="$BATS_TEST_TMPDIR/routes.json"
  export NEW_GATEWAY_STATE="pending"   # pending | accepted | rejected | detached
  unset SERVICE_TO_SERVICE_KEEP_PREVIOUS SERVICE_TO_SERVICE_ROLLBACK SERVICE_TO_SERVICE_MOVE_PENDING_GATEWAY

  export CONTEXT='{
    "k8s_namespace": "apps",
    "scope": {"id": 123},
    "names": {"stable_service": "checkout"},
    "service_to_service": {"enabled": true, "mode": "shared", "gateway_name": "gateway-in-cluster", "gateway_namespace": "gateways",
      "gateway_host": "gateway-in-cluster-istio.gateways.svc.cluster.local", "listener_prefix": "in-cluster-",
      "hostnames": ["checkout.apps.svc.cluster.local"], "ports": [8080, 9090], "grpc_ports": [9090]}
  }'

  # Live routes on the private gateway (accepted), the new one, and a gateway that rejected them.
  cat > "$ROUTES_FILE" <<'JSON'
{"items": [
  {"metadata": {"name": "checkout-http-8080"},
   "spec": {"hostnames": ["checkout.apps.svc.cluster.local", "checkout.apps"]},
   "status": {"parents": [
    {"parentRef": {"name": "gateway-private", "namespace": "gateways", "sectionName": "s2s-8080"},
     "conditions": [{"type": "Accepted", "status": "True"}]},
    {"parentRef": {"name": "gateway-in-cluster", "namespace": "gateways", "sectionName": "in-cluster-8080"},
     "conditions": [{"type": "Accepted", "status": "True"}]},
    {"parentRef": {"name": "gateway-old", "namespace": "gateways", "sectionName": "in-cluster-8080"},
     "conditions": [{"type": "Accepted", "status": "False"}]}]}},
  {"metadata": {"name": "checkout-grpc-9090"}, "status": {"parents": [
    {"parentRef": {"name": "gateway-private", "sectionName": "s2s-9090"},
     "conditions": [{"type": "Accepted", "status": "True"}]}]}},
  {"metadata": {"name": "other-http-8080"}, "status": {"parents": [
    {"parentRef": {"name": "gateway-private", "namespace": "gateways"},
     "conditions": [{"type": "Accepted", "status": "True"}]}]}}
]}
JSON

  kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    case "$1 $2" in
      "get service")
        if [[ "$*" == *jsonpath* ]]; then echo -n "$LIVE_HOST"; return 0; fi
        jq -n --arg host "$LIVE_HOST" --arg saved "$SAVED_HOSTNAMES" \
          '{spec: {externalName: $host}, metadata: {annotations: (if $saved != "" then {"nullplatform.io/previous-hostnames": $saved} else {} end)}}' ;;
      "get httproute")
        if [ "$3" = "-n" ]; then cat "$ROUTES_FILE"; return 0; fi
        case "$NEW_GATEWAY_STATE" in
          detached) echo '{"spec": {"parentRefs": [{"name": "gateway-private", "namespace": "gateways"}]}}' ;;
          accepted) echo '{"metadata": {"generation": 2}, "spec": {"parentRefs": [{"name": "gateway-in-cluster", "namespace": "gateways"}]}, "status": {"parents": [{"parentRef": {"name": "gateway-in-cluster", "namespace": "gateways"}, "conditions": [{"type": "Accepted", "status": "True", "observedGeneration": 2}]}]}}' ;;
          rejected) echo '{"metadata": {"generation": 2}, "spec": {"parentRefs": [{"name": "gateway-in-cluster", "namespace": "gateways"}]}, "status": {"parents": [{"parentRef": {"name": "gateway-in-cluster", "namespace": "gateways"}, "conditions": [{"type": "Accepted", "status": "False", "reason": "NoMatchingListenerHostname", "observedGeneration": 2}]}]}}' ;;
          *) echo '{"metadata": {"generation": 2}, "spec": {"parentRefs": [{"name": "gateway-in-cluster", "namespace": "gateways"}]}, "status": {"parents": []}}' ;;
        esac ;;
      "patch service") echo "service/checkout patched" ;;
    esac
  }
  export -f kubectl
  source "$PROJECT_ROOT/k8s/deployment/networking/gateway/service_to_service_gateway_move"
}

@test "gateway move: while moving, keeps the ExternalName, every accepted parent of another gateway and the live hostnames" {
  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -r .service_to_service.external_name)" "$LIVE_HOST"
  assert_equal "$(echo "$CONTEXT" | jq -c .service_to_service.previous_parents)" \
    '{"8080":[{"name":"gateway-private","namespace":"gateways","sectionName":"s2s-8080"}],"9090":[{"name":"gateway-private","namespace":"apps","sectionName":"s2s-9090"}]}'
  assert_equal "$(echo "$CONTEXT" | jq -c .service_to_service.previous_hostnames)" '["checkout.apps.svc.cluster.local","checkout.apps"]'
}

@test "gateway move: the hostnames saved on the Service win over the live route's while the move is pending" {
  export SAVED_HOSTNAMES='["checkout.apps.svc.cluster.local","checkout.apps","saved"]'

  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -r '.service_to_service.previous_hostnames[-1]')" "saved"
}

@test "gateway move: not moving, drops the old parents (finalize, rollback, initial)" {
  export LIVE_HOST="gateway-in-cluster-istio.gateways.svc.cluster.local"

  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -c '.service_to_service | [has("external_name"), has("previous_parents"), has("previous_hostnames")]')" '[false,false,false]'
}

@test "gateway move: not moving, keeps the old parents while blue still serves (blue-green start, switch)" {
  export LIVE_HOST="gateway-in-cluster-istio.gateways.svc.cluster.local"
  export SERVICE_TO_SERVICE_KEEP_PREVIOUS=true

  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -r '.service_to_service | has("external_name")')" "false"
  assert_equal "$(echo "$CONTEXT" | jq -r '.service_to_service.previous_parents | keys | join(",")')" "8080,9090"
}

@test "gateway move: a rollback while the move is pending renders the live gateway, its listeners and hostnames" {
  export SERVICE_TO_SERVICE_ROLLBACK=true

  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -c '.service_to_service | [.gateway_name, .gateway_namespace, .listener_prefix, .gateway_host]')" \
    '["gateway-private","gateways","s2s-","gateway-private-istio.gateways.svc.cluster.local"]'
  assert_equal "$(echo "$CONTEXT" | jq -c '.service_to_service.hostnames')" '["checkout.apps.svc.cluster.local","checkout.apps"]'
  assert_equal "$(echo "$CONTEXT" | jq -c '.service_to_service | [has("external_name"), has("previous_parents"), has("previous_hostnames")]')" '[false,false,false]'
}

@test "gateway move: a rollback with no move pending renders the configured gateway" {
  export LIVE_HOST="gateway-in-cluster-istio.gateways.svc.cluster.local"
  export SERVICE_TO_SERVICE_ROLLBACK=true

  service_to_service_previous_gateway

  assert_equal "$(echo "$CONTEXT" | jq -r '.service_to_service.gateway_name')" "gateway-in-cluster"
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

  service_to_service_finish_gateway_move

  [[ "$(cat "$KUBECTL_LOG")" != *"patch"* ]] || false
  assert_equal "$SERVICE_TO_SERVICE_MOVE_PENDING_GATEWAY" ""
}

@test "gateway move: finish switches the ExternalName once the new gateway accepts every internal route" {
  export NEW_GATEWAY_STATE=accepted

  run service_to_service_finish_gateway_move

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_LOG")" 'patch service checkout -n apps --type merge -p {"spec":{"externalName":"gateway-in-cluster-istio.gateways.svc.cluster.local"}}'
  assert_contains "$output" "✅ checkout now resolves to gateway-in-cluster-istio.gateways.svc.cluster.local"
  service_to_service_finish_gateway_move >/dev/null
  assert_equal "$SERVICE_TO_SERVICE_MOVE_PENDING_GATEWAY" ""
}

@test "gateway move: finish keeps the old gateway when the new one never accepts the routes, and leaves the move pending" {
  export SERVICE_TO_SERVICE_MOVE_TIMEOUT_SECONDS=4

  run service_to_service_finish_gateway_move

  [ "$status" -eq 0 ]
  [[ "$(cat "$KUBECTL_LOG")" != *"patch"* ]] || false
  assert_contains "$output" "has not accepted checkout-http-8080 checkout-grpc-9090 after 4s; checkout keeps pointing at $LIVE_HOST"
  service_to_service_finish_gateway_move >/dev/null
  assert_equal "$SERVICE_TO_SERVICE_MOVE_PENDING_GATEWAY" "gateways/gateway-in-cluster"
}

@test "gateway move: finish stops waiting as soon as the new gateway rejects a route" {
  export NEW_GATEWAY_STATE=rejected SERVICE_TO_SERVICE_MOVE_TIMEOUT_SECONDS=600

  run service_to_service_finish_gateway_move

  [ "$status" -eq 0 ]
  [[ "$(cat "$KUBECTL_LOG")" != *"patch"* ]] || false
  assert_contains "$output" "Gateway gateways/gateway-in-cluster rejected checkout-http-8080 checkout-grpc-9090; checkout keeps pointing at $LIVE_HOST"
  [ "$(grep -c 'get httproute checkout-http-8080' "$KUBECTL_LOG")" -le 2 ]
}

@test "gateway move: finish does not wait when a rollback left the routes on the live gateway only" {
  export NEW_GATEWAY_STATE=detached

  run service_to_service_finish_gateway_move

  [ "$status" -eq 0 ]
  [[ "$(cat "$KUBECTL_LOG")" != *"patch"* ]] || false
  assert_contains "$output" "not attached to gateways/gateway-in-cluster; checkout stays on $LIVE_HOST"
}
