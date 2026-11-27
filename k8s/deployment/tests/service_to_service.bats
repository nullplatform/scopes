#!/usr/bin/env bats
# =============================================================================
# Unit tests for the service-to-service checks of deployment/build_context
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  unset GATEWAY_TYPE INITIAL_INGRESS_PATH BLUE_GREEN_INGRESS_PATH SERVICE_TO_SERVICE_ENABLED SERVICE_TO_SERVICE_MODE
  eval "$(sed -n '/^NP_SERVICE_TO_SERVICE_RESERVED_PORTS=/p; /^resolve_service_to_service_ports()/,/^}/p' "$PROJECT_ROOT/k8s/deployment/build_context")"

  export MAIN_HTTP_PORT=8080
  export CONTEXT='{
    "service_to_service": {"enabled": true},
    "scope": {"capabilities": {"additional_ports": [
      {"port": 8081, "type": "HTTP"},
      {"port": 9090, "type": "GRPC"},
      {"port": 8080, "type": "HTTP"}
    ]}}
  }'
}

@test "service_to_service: lists the main port first, then additional HTTP and GRPC ports, without duplicates" {
  run resolve_service_to_service_ports

  [ "$status" -eq 0 ]
  assert_equal "$output" "[8080,8081,9090]"
}

@test "service_to_service: prints nothing when disabled" {
  export CONTEXT='{"scope": {"capabilities": {}}}'
  export INITIAL_INGRESS_PATH='$SERVICE_PATH/deployment/templates/initial-ingress.yaml.tpl'

  run resolve_service_to_service_ports

  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "service_to_service: accepts the istio HTTPRoute templates" {
  export INITIAL_INGRESS_PATH='$SERVICE_PATH/deployment/templates/istio/initial-httproute.yaml.tpl'
  export BLUE_GREEN_INGRESS_PATH='$SERVICE_PATH/deployment/templates/istio/blue-green-httproute.yaml.tpl'

  run resolve_service_to_service_ports

  [ "$status" -eq 0 ]
  assert_equal "$output" "[8080,8081,9090]"
}

@test "service_to_service: fails with the ALB ingress templates" {
  export INITIAL_INGRESS_PATH='$SERVICE_PATH/deployment/templates/initial-ingress.yaml.tpl'

  run resolve_service_to_service_ports

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ service_to_service needs the Istio gateway ingress templates, but this scope uses: \$SERVICE_PATH/deployment/templates/initial-ingress.yaml.tpl"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   • Or disable networking.service_to_service.enabled for this scope"
}

@test "service_to_service: fails when only the blue-green template is not istio" {
  export INITIAL_INGRESS_PATH='$SERVICE_PATH/deployment/templates/istio/initial-httproute.yaml.tpl'
  export BLUE_GREEN_INGRESS_PATH='$SERVICE_PATH/deployment/templates/blue-green-ingress.yaml.tpl'

  run resolve_service_to_service_ports

  [ "$status" -eq 1 ]
  assert_contains "$output" "but this scope uses: \$SERVICE_PATH/deployment/templates/blue-green-ingress.yaml.tpl"
}

@test "service_to_service: fails on ARO clusters" {
  export GATEWAY_TYPE=aro_cluster

  run resolve_service_to_service_ports

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ service_to_service is not supported with GATEWAY_TYPE 'aro_cluster'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

@test "service_to_service: fails on ports the gateway reserves" {
  export MAIN_HTTP_PORT=15021
  export CONTEXT='{"service_to_service": {"enabled": true}, "scope": {"capabilities": {"additional_ports": [{"port": 443, "type": "HTTP"}, {"port": 15090, "type": "GRPC"}]}}}'

  run resolve_service_to_service_ports

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ service_to_service cannot expose port(s) 15021, 443, 15090: the gateway reserves them"
}

@test "service_to_service: a failing check aborts the full build_context" {
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SERVICE_ACTION="start-initial"
  export DNS_TYPE="external_dns"
  export SERVICE_TO_SERVICE_ENABLED=true
  export INITIAL_INGRESS_PATH='$SERVICE_PATH/deployment/templates/initial-ingress.yaml.tpl'
  kubectl() { return 0; }
  export -f kubectl
  export CONTEXT='{
    "scope": {"id": "123", "slug": "prod", "nrn": "nrn:organization=1:account=2:namespace=3:application=4", "domain": "x.io",
      "capabilities": {"visibility": "private", "scaling_type": "fixed", "fixed_instances": 1, "protocol": "http"}},
    "namespace": {"slug": "ns"}, "application": {"slug": "app"},
    "deployment": {"id": "456", "status": "creating"},
    "providers": {"container-orchestration": {"cluster": {"namespace": "apps"}}}
  }'

  run source "$PROJECT_ROOT/k8s/deployment/build_context"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ service_to_service needs the Istio gateway ingress templates"
  rm -rf "$NP_OUTPUT_DIR"
}

@test "service_to_service: the full build_context adds the HTTP and GRPC ports and the stable name" {
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SERVICE_ACTION="start-initial"
  export DNS_TYPE="external_dns"
  export SERVICE_TO_SERVICE_ENABLED=true
  kubectl() { return 0; }
  export -f kubectl
  export CONTEXT='{
    "scope": {"id": "123", "slug": "prod", "nrn": "nrn:organization=1:account=2:namespace=3:application=4", "domain": "x.io",
      "capabilities": {"visibility": "private", "scaling_type": "fixed", "fixed_instances": 1, "protocol": "http",
        "main_http_port": 3000, "additional_ports": [{"port": 3001, "type": "HTTP"}, {"port": 3002, "type": "GRPC"}]}},
    "namespace": {"slug": "ns"}, "application": {"slug": "app"},
    "deployment": {"id": "456", "status": "creating"},
    "providers": {"container-orchestration": {"cluster": {"namespace": "apps"}}}
  }'

  source "$PROJECT_ROOT/k8s/deployment/build_context" >/dev/null

  assert_equal "$(echo "$CONTEXT" | jq -c .service_to_service.ports)" "[3000,3001,3002]"
  assert_equal "$(echo "$CONTEXT" | jq -c .service_to_service.grpc_ports)" "[3002]"
  assert_equal "$(echo "$CONTEXT" | jq -r .names.stable_service)" "app-prod"
  assert_equal "$(echo "$CONTEXT" | jq -c .service_to_service.hostnames)" '["app-prod.apps.svc.cluster.local"]'
  rm -rf "$NP_OUTPUT_DIR"
}

@test "service_to_service: never blocks deleting or rolling back a deployment" {
  export INITIAL_INGRESS_PATH='$SERVICE_PATH/deployment/templates/initial-ingress.yaml.tpl'
  export GATEWAY_TYPE=aro_cluster
  for action in delete-deployment rollback-deployment; do
    export SERVICE_ACTION=$action
    run resolve_service_to_service_ports
    [ "$status" -eq 0 ]
    assert_equal "$output" "[8080,8081,9090]"
  done
}
