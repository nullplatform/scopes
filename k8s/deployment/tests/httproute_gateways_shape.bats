#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export TPL_DIR="$PROJECT_ROOT/k8s/deployment/templates/istio"
  export INITIAL="$TPL_DIR/initial-httproute.yaml.tpl"
  export BLUE_GREEN="$TPL_DIR/blue-green-httproute.yaml.tpl"
}

_context() {
  cat <<'JSON'
{
  "account": {"id": "acc1", "slug": "acct"},
  "namespace": {"id": "ns1", "slug": "nsps"},
  "application": {"id": "app1", "slug": "appslug"},
  "scope": {"id": "scope-123", "slug": "scopeslug", "domain": "platform.example.com", "domains": []},
  "deployment": {"id": "deploy-456", "strategy_data": {"desired_switched_traffic": 50}},
  "names": {
    "deployment": "d-scope-123-deploy-456",
    "scope_ingress": "k-8-s-scopeslug-scope-123-internal",
    "blue_service": "d-scope-123-deploy-123"
  },
  "k8s_namespace": "ns-test",
  "k8s_modifiers": {},
  "gateway_name": "gateway-internal",
  "main_http_port": 8080
}
JSON
}

_render() {
  local tpl="$1" filter="$2"
  local ctx="$BATS_TEST_TMPDIR/ctx.json"
  _context | jq "$filter" > "$ctx"
  gomplate -c .="$ctx" -f "$tpl"
}

_parent_refs() {
  echo "$1" | yq -N -o=json '.spec.parentRefs' | jq -c 'map({name, namespace})'
}

@test "initial-httproute: references every configured gateway" {
  rendered=$(_render "$INITIAL" '. + {gateways: [{name: "gateway-internal", namespace: "istio-gw"}, {name: "partners", namespace: "edge"}]}')

  assert_equal "$(_parent_refs "$rendered")" '[{"name":"gateway-internal","namespace":"istio-gw"},{"name":"partners","namespace":"edge"}]'
}

@test "blue-green-httproute: references every configured gateway" {
  rendered=$(_render "$BLUE_GREEN" '. + {gateways: [{name: "gateway-internal", namespace: "istio-gw"}, {name: "partners", namespace: "edge"}]}')

  assert_equal "$(_parent_refs "$rendered")" '[{"name":"gateway-internal","namespace":"istio-gw"},{"name":"partners","namespace":"edge"}]'
}

@test "initial-httproute: without gateways in the context keeps the gateway_name in the gateways namespace" {
  rendered=$(_render "$INITIAL" '.')

  assert_equal "$(_parent_refs "$rendered")" '[{"name":"gateway-internal","namespace":"gateways"}]'
}

@test "blue-green-httproute: without gateways in the context keeps the gateway_name in the gateways namespace" {
  rendered=$(_render "$BLUE_GREEN" '.')

  assert_equal "$(_parent_refs "$rendered")" '[{"name":"gateway-internal","namespace":"gateways"}]'
}

@test "initial-httproute: parentRefs keep the Gateway API group and kind" {
  rendered=$(_render "$INITIAL" '. + {gateways: [{name: "a", namespace: "x"}, {name: "b", namespace: "y"}]}')

  assert_equal "$(echo "$rendered" | yq -N -o=json '.spec.parentRefs' | jq -c 'map(.group + "/" + .kind) | unique')" '["gateway.networking.k8s.io/Gateway"]'
}
