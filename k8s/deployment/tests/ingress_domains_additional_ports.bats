#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export TPL_DIR="$PROJECT_ROOT/k8s/deployment/templates"
  export INITIAL="$TPL_DIR/initial-ingress.yaml.tpl"
  export BLUE_GREEN="$TPL_DIR/blue-green-ingress.yaml.tpl"
}

_context() {
  cat <<'JSON'
{
  "account": {"id": "acc1", "slug": "acct"},
  "namespace": {"id": "ns1", "slug": "nsps"},
  "application": {"id": "app1", "slug": "appslug"},
  "scope": {
    "id": "scope-123",
    "slug": "scopeslug",
    "domain": "platform.example.com",
    "domains": [
      {"id": "dom-1", "name": "custom-one.example.com", "status": "active", "type": "scope"},
      {"id": "dom-2", "name": "custom-two.example.com", "status": "active", "type": "scope"}
    ],
    "capabilities": {
      "main_http_port": 8080,
      "additional_ports": [
        {"port": 8081, "type": "HTTP", "traffic_manager_port": 18081},
        {"port": 9012, "type": "GRPC", "traffic_manager_port": 19012}
      ]
    }
  },
  "deployment": {"id": "deploy-456", "strategy_data": {"desired_switched_traffic": 50}},
  "blue_deployment_id": "deploy-123",
  "blue_additional_port_services": {"http-8081": true, "grpc-9012": true},
  "k8s_namespace": "ns-test",
  "k8s_modifiers": {},
  "alb_name": "k8s-test-alb",
  "ingress_visibility": "internal",
  "main_http_port": 8080
}
JSON
}

_render() {
  local tpl="$1"
  local ctx="$BATS_TEST_TMPDIR/ctx.json"
  _context > "$ctx"
  gomplate -c .="$ctx" -f "$tpl"
}

_backend() {
  local rendered="$1" ingress="$2" host="$3"
  echo "$rendered" | yq -N "select(.metadata.name == \"$ingress\") | .spec.rules[] | select(.host == \"$host\") | .http.paths[0].backend.service | .name + \":\" + (.port.number // .port.name | tostring)"
}

_path() {
  local rendered="$1" ingress="$2" host="$3"
  echo "$rendered" | yq -N "select(.metadata.name == \"$ingress\") | .spec.rules[] | select(.host == \"$host\") | .http.paths[0].path"
}

@test "initial-ingress: renders when a scope has both custom domains and additional ports" {
  run _render "$INITIAL"
  [ "$status" -eq 0 ]
}

@test "initial-ingress: custom domains route each additional port to its own service" {
  rendered=$(_render "$INITIAL")

  for host in custom-one.example.com custom-two.example.com; do
    assert_equal "d-scope-123-deploy-456-http-8081:8081" \
      "$(_backend "$rendered" k-8-s-scopeslug-scope-123-http-8081-internal "$host")"
    assert_equal "d-scope-123-deploy-456-grpc-9012:9012" \
      "$(_backend "$rendered" k-8-s-scopeslug-scope-123-grpc-9012-internal "$host")"
  done
}

@test "initial-ingress: custom domain rules match the platform domain rule" {
  rendered=$(_render "$INITIAL")

  for ingress in k-8-s-scopeslug-scope-123-http-8081-internal k-8-s-scopeslug-scope-123-grpc-9012-internal; do
    platform=$(_backend "$rendered" "$ingress" platform.example.com)
    for host in custom-one.example.com custom-two.example.com; do
      assert_equal "$platform" "$(_backend "$rendered" "$ingress" "$host")"
    done
  done
}

@test "initial-ingress: every rendered document is valid yaml with a name" {
  rendered=$(_render "$INITIAL")

  names=$(echo "$rendered" | yq -N '.metadata.name')
  assert_equal 3 "$(echo "$names" | grep -c .)"
  if echo "$names" | grep -q 'null'; then
    echo "a rendered document lost its metadata.name: $rendered"
    return 1
  fi
}

@test "blue-green-ingress: renders when a scope has both custom domains and additional ports" {
  run _render "$BLUE_GREEN"
  [ "$status" -eq 0 ]
}

@test "blue-green-ingress: custom domains route each additional port through its own annotation action" {
  rendered=$(_render "$BLUE_GREEN")

  for host in custom-one.example.com custom-two.example.com; do
    assert_equal "bg-deployment-http-8081:use-annotation" \
      "$(_backend "$rendered" k-8-s-scopeslug-scope-123-http-8081-internal "$host")"
    assert_equal "bg-deployment-grpc-9012:use-annotation" \
      "$(_backend "$rendered" k-8-s-scopeslug-scope-123-grpc-9012-internal "$host")"
  done
}

@test "blue-green-ingress: each additional port keeps its own path shape on custom domains" {
  rendered=$(_render "$BLUE_GREEN")

  for host in custom-one.example.com custom-two.example.com; do
    assert_equal "/8081" "$(_path "$rendered" k-8-s-scopeslug-scope-123-http-8081-internal "$host")"
    assert_equal "/" "$(_path "$rendered" k-8-s-scopeslug-scope-123-grpc-9012-internal "$host")"
  done
}
