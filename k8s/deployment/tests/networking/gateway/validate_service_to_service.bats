#!/usr/bin/env bats
# =============================================================================
# Unit tests for the service-to-service checks of
# deployment/networking/gateway/validate_gateways
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCRIPT="$PROJECT_ROOT/k8s/deployment/networking/gateway/validate_gateways"
  export SCOPE_VISIBILITY="private"
  export INVALID_ADDITIONAL_GATEWAYS=""
  export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  export LISTENERS_FIXTURE='["http","in-cluster-80","in-cluster-8080","in-cluster-8081"]'
  export IN_CLUSTER_GATEWAY_FIXTURE="found"
  export STABLE_SERVICE_FIXTURE="absent"

  export CONTEXT='{
    "k8s_namespace": "apps",
    "scope": {"id": 123},
    "names": {"stable_service": "checkout-api-production"},
    "gateway_name": "gateway-internal",
    "gateways": [{"name": "gateway-internal", "namespace": "gateways"}],
    "service_to_service": {
      "enabled": true, "mode": "shared",
      "gateway_name": "gateway-internal", "gateway_namespace": "gateways",
      "listener_prefix": "in-cluster-",
      "ports": [8080, 8081],
      "hostnames": ["checkout-api-production.apps.svc.cluster.local"]
    }
  }'

  kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    case "$2 $*" in
      "gateway "*"-o name"*) echo "gateway.gateway.networking.k8s.io/$3" ;;
      "gateway "*"-o json"*)
        case "$IN_CLUSTER_GATEWAY_FIXTURE" in
          found) jq -n --argjson names "$LISTENERS_FIXTURE" '{spec: {listeners: [$names[] | {name: ., port: 80, protocol: "HTTP"}]}}' ;;
          missing) echo "Error from server (NotFound): gateways.gateway.networking.k8s.io \"$3\" not found" >&2; return 1 ;;
          forbidden) echo "Error from server (Forbidden): gateways.gateway.networking.k8s.io \"$3\" is forbidden" >&2; return 1 ;;
        esac ;;
      "service "*)
        case "$STABLE_SERVICE_FIXTURE" in
          absent) echo "Error from server (NotFound): services \"$3\" not found" >&2; return 1 ;;
          ours) echo '{"metadata":{"labels":{"scope_id":"123","nullplatform.io/stable-service":"true"}}}' ;;
          other-scope) echo '{"metadata":{"labels":{"scope_id":"999","nullplatform.io/stable-service":"true"}}}' ;;
          foreign) echo '{"metadata":{"labels":{"app":"legacy"}}}' ;;
          forbidden) echo "Error from server (Forbidden): services \"$3\" is forbidden" >&2; return 1 ;;
        esac ;;
    esac
  }
  export -f kubectl

  for helper in np_scope_step_begin np_scope_step_end np_scope_explain np_scope_input np_scope_output np_scope_consumes np_scope_failure; do
    eval "$helper() { :; }"
    export -f "$helper"
  done
}

mock_tracing() {
  export TRACE_LOG="$BATS_TEST_TMPDIR/trace.log"
  for helper in np_scope_step_begin np_scope_step_end np_scope_explain np_scope_input np_scope_output np_scope_consumes np_scope_failure; do
    eval "$helper() { echo \"$helper \$*\" >> \"\$TRACE_LOG\"; }"
    export -f "$helper"
  done
}

@test "service_to_service: not validated when disabled" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.service_to_service)')

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_equal "$(cat "$KUBECTL_LOG")" "get gateway gateway-internal -n gateways -o name"
  [[ "$output" != *"Service-to-service"* ]] || false
}

@test "service_to_service: succeeds when the gateway has every listener and the name is free" {
  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ All gateways exist: gateways/gateway-internal"
  assert_contains "$output" "✅ Service-to-service routing ready: checkout-api-production.apps.svc.cluster.local through gateways/gateway-internal"
  assert_contains "$(cat "$KUBECTL_LOG")" "get gateway gateway-internal -n gateways -o json"
  assert_contains "$(cat "$KUBECTL_LOG")" "get service checkout-api-production -n apps -o json"
}

@test "service_to_service: succeeds when the stable Service already belongs to this scope" {
  export STABLE_SERVICE_FIXTURE="ours"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Service-to-service routing ready"
}

@test "service_to_service: fails naming every missing listener" {
  export LISTENERS_FIXTURE='["http","in-cluster-80"]'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Gateway 'gateways/gateway-internal' has no listener for the scope's HTTP ports: in-cluster-8080 in-cluster-8081"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   - Add the ports to gateway.inCluster.ports (base chart) or gateway_in_cluster_ports (base tofu module)"
  [[ "$(cat "$KUBECTL_LOG")" != *"get service"* ]] || false
}

@test "service_to_service: honours a custom listener prefix" {
  export LISTENERS_FIXTURE='["s2s-8080","s2s-8081"]'
  export CONTEXT=$(echo "$CONTEXT" | jq '.service_to_service.listener_prefix = "s2s-"')

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
}

@test "service_to_service: fails when the in-cluster gateway does not exist" {
  export IN_CLUSTER_GATEWAY_FIXTURE="missing"
  export CONTEXT=$(echo "$CONTEXT" | jq '.service_to_service.mode = "dedicated" | .service_to_service.gateway_name = "gateway-in-cluster"')

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ In-cluster gateway 'gateways/gateway-in-cluster' not found"
  assert_contains "$output" "   - The in-cluster gateway is not installed (gateway.inCluster in the base chart, gateway_in_cluster_enabled in the base tofu module)"
}

@test "service_to_service: reports an API error on the gateway separately from a missing one" {
  export IN_CLUSTER_GATEWAY_FIXTURE="forbidden"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not check gateway 'gateways/gateway-internal'"
  [[ "$output" != *"not found"* ]] || false
}

@test "service_to_service: fails when another scope owns the stable name" {
  export STABLE_SERVICE_FIXTURE="other-scope"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Service 'apps/checkout-api-production' already exists and is not this scope's stable service"
  assert_contains "$output" "it belongs to scope_id=999"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   - Set a service_to_service.name_pattern that is unique in namespace 'apps'"
}

@test "service_to_service: fails when a Service created outside nullplatform has the stable name" {
  export STABLE_SERVICE_FIXTURE="foreign"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Service 'apps/checkout-api-production' already exists and is not this scope's stable service"
  [[ "$output" != *"it belongs to scope_id"* ]] || false
}

@test "service_to_service: fails when the stable name cannot be checked" {
  export STABLE_SERVICE_FIXTURE="forbidden"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not check service 'apps/checkout-api-production'"
}

@test "service_to_service: traces its own validation step" {
  mock_tracing

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$TRACE_LOG")" 'np_scope_step_end 0
np_scope_step_begin validate-service-to-service --title Validate service-to-service routing
np_scope_input service_to_service {"mode":"shared","gateway":"gateways/gateway-internal","ports":[8080,8081],"hostnames":["checkout-api-production.apps.svc.cluster.local"]}
np_scope_consumes k8s-gateway:gateways/gateway-internal
np_scope_explain --title Validate service-to-service routing --what checkout-api-production.apps.svc.cluster.local routes through gateways/gateway-internal
np_scope_step_end 0'
}

@test "service_to_service: fails the trace step with the missing listeners" {
  mock_tracing
  export LISTENERS_FIXTURE='[]'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$(cat "$TRACE_LOG")" 'np_scope_output missing_listeners ["in-cluster-8080","in-cluster-8081"]'
  assert_contains "$(cat "$TRACE_LOG")" "np_scope_failure ListenerNotFound
np_scope_step_end 1 Gateway gateways/gateway-internal has no listener: in-cluster-8080 in-cluster-8081"
}

@test "service_to_service: fails the trace step on a name collision" {
  mock_tracing
  export STABLE_SERVICE_FIXTURE="other-scope"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$(cat "$TRACE_LOG")" "np_scope_failure StableServiceNameTaken
np_scope_step_end 1 Service apps/checkout-api-production already exists"
}
