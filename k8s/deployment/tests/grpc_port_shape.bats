#!/usr/bin/env bats
# =============================================================================
# Structural + rendering tests for GRPC additional ports.
#
# A GRPC additional port follows the same convention as an HTTP one: the
# application binds the port it declared, and its traffic-manager sidecar binds
# <port>+10000. Before this was aligned the sidecar bound <port> itself, so the
# application could not open its own gRPC listener — every container in a pod
# shares one network namespace, so it got EADDRINUSE.
#
# That bug stayed invisible for months because the traffic-manager image used
# to ignore LISTENER_PORT: nginx fell back to port 80, collided with the main
# sidecar, died, and start.sh (which never checks nginx's exit code) kept the
# container alive. Traffic went straight from the Service to the application.
# These tests pin the pieces that have to move together.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export TPL_DIR="$PROJECT_ROOT/k8s/deployment/templates"
  export DEPLOYMENT="$TPL_DIR/deployment.yaml.tpl"
  export SERVICE="$TPL_DIR/service.yaml.tpl"
}

# -----------------------------------------------------------------------------
# Structural — grep the template sources
# -----------------------------------------------------------------------------

@test "deployment: grpc sidecar binds traffic_manager_port, not the declared port" {
  # The gRPC probes are the only `grpc:` blocks in the template.
  count=$(grep -A1 '^            grpc:' "$DEPLOYMENT" | grep -c 'port: {{ .traffic_manager_port }}')
  [ "$count" -eq 3 ]
  ! grep -A1 '^            grpc:' "$DEPLOYMENT" | grep -q 'port: {{ .port }}'
}

@test "deployment: grpc sidecar receives UPSTREAM_PORT pointing at the application port" {
  # Without it the image falls back to its own default of 8080, which silently
  # breaks any scope whose gRPC server does not happen to listen there.
  grpc_branch=$(awk '/{{ if eq .type "GRPC" }}/,/{{ else if eq .type "HTTP" }}/' "$DEPLOYMENT")
  assert_contains "$grpc_branch" "name: UPSTREAM_PORT"
  assert_contains "$grpc_branch" "value: '{{ .port }}'"
}

@test "deployment: application container ports block does not filter by type" {
  # Both HTTP and GRPC entries are bound by the application now, so a type
  # guard here would drop the gRPC port from the rendered spec.
  app_ports=$(awk '/- containerPort: {{ .main_http_port }}/,/resources:/' "$DEPLOYMENT")
  assert_contains "$app_ports" "containerPort: {{ .port }}"
  if echo "$app_ports" | grep -q 'eq .type'; then
    echo "application ports block still filters on port type"
    return 1
  fi
}

@test "service: grpc service targets the sidecar port" {
  # port stays the declared one (external contract), targetPort moves.
  ! grep -qE 'targetPort: \{\{ \.port \}\}' "$SERVICE"
  count=$(grep -c 'targetPort: {{ .traffic_manager_port }}' "$SERVICE")
  [ "$count" -eq 2 ]
}

# -----------------------------------------------------------------------------
# Rendering — real gomplate against the templates
# -----------------------------------------------------------------------------

_grpc_context() {
  cat <<'JSON'
{
  "account": {"id": "acc1", "slug": "acct"},
  "namespace": {"id": "ns1", "slug": "nsps"},
  "application": {"id": "app1", "slug": "appslug"},
  "release": {"semver": "1.0.0"},
  "scope": {
    "id": "scope-123",
    "slug": "scopeslug",
    "domain": "x.example.com",
    "domains": [],
    "dimensions": {"env": "dev"},
    "capabilities": {
      "cpu_millicores": 100,
      "ram_memory": 128,
      "cpu_millicores_limit": 200,
      "ram_memory_limit": 256,
      "additional_ports": [{"port": 9090, "type": "GRPC", "traffic_manager_port": 19090}],
      "scaling_type": "fixed",
      "autoscaling": {
        "min_replicas": 1,
        "max_replicas": 3,
        "target_cpu_utilization": 80,
        "target_memory_enabled": false,
        "target_memory_utilization": 80
      },
      "health_check": {"path": "/health", "timeout_seconds": 1, "period_seconds": 5, "initial_delay_seconds": 5}
    }
  },
  "deployment": {"id": "deploy-456"},
  "k8s_namespace": "ns-test",
  "k8s_modifiers": {},
  "asset": {"url": "example.com/app:latest"},
  "main_http_port": 8080,
  "main_traffic_manager_port": 80,
  "traffic_image": "example.com/traffic:latest",
  "container_cpu_in_millicores": 50,
  "container_memory_in_memory": 64,
  "pull_secrets": {"ENABLED": false, "SECRETS": []},
  "region": "us-east-1",
  "component": "app",
  "service_account_name": "",
  "traffic_manager_config_map": "",
  "replicas": 1,
  "parameters": {"results": []}
}
JSON
}

_render() {
  local tpl="$1"
  local ctx="$BATS_TEST_TMPDIR/ctx.json"
  _grpc_context > "$ctx"
  gomplate -c .="$ctx" -f "$tpl"
}

@test "render: grpc sidecar listens on 19090 and proxies to 9090" {
  run _render "$DEPLOYMENT"
  [ "$status" -eq 0 ]

  # The sidecar container block, from its name down to its probes.
  sidecar=$(echo "$output" | awk '/- name: grpc-9090/,/imagePullPolicy/')

  assert_contains "$sidecar" "containerPort: 19090"
  assert_contains "$sidecar" "name: UPSTREAM_PORT"
  assert_contains "$sidecar" "value: '9090'"
  assert_contains "$sidecar" "name: LISTENER_PORT"
  assert_contains "$sidecar" "value: '19090'"
  assert_contains "$sidecar" "port: 19090"

  # The application port must never appear as the sidecar's listener.
  if echo "$sidecar" | grep -q "containerPort: 9090"; then
    echo "sidecar still binds the application port 9090"
    return 1
  fi
}

@test "render: application container declares the gRPC port it binds" {
  run _render "$DEPLOYMENT"
  [ "$status" -eq 0 ]

  app=$(echo "$output" | awk '/- name: application/,/lifecycle:/')
  assert_contains "$app" "containerPort: 8080"
  assert_contains "$app" "containerPort: 9090"

  # The sidecar port belongs to the sidecar, not the application.
  if echo "$app" | grep -q "containerPort: 19090"; then
    echo "application container should not declare the sidecar port"
    return 1
  fi
}

@test "render: grpc Service exposes 9090 and targets the sidecar on 19090" {
  run _render "$SERVICE"
  [ "$status" -eq 0 ]

  svc=$(echo "$output" | awk '/d-scope-123-deploy-456-grpc-9090/,0')
  assert_contains "$svc" "port: 9090"
  assert_contains "$svc" "targetPort: 19090"
}
