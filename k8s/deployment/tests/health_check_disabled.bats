#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export DEPLOYMENT="$PROJECT_ROOT/k8s/deployment/templates/deployment.yaml.tpl"
}

_context() {
  local health_check="$1"
  cat <<JSON
{
  "account": {"id": "acc1", "slug": "acct"},
  "namespace": {"id": "ns1", "slug": "nsps"},
  "application": {"id": "app1", "slug": "appslug"},
  "scope": {
    "id": "scope-123",
    "slug": "scopeslug",
    "domain": "platform.example.com",
    "domains": [],
    "dimensions": {"env": "dev"},
    "capabilities": {
      "cpu_millicores": 100,
      "ram_memory": 128,
      "cpu_millicores_limit": 200,
      "ram_memory_limit": 256,
      "main_http_port": 8080,
      "additional_ports": [
        {"port": 8081, "type": "HTTP", "traffic_manager_port": 18081},
        {"port": 9012, "type": "GRPC", "traffic_manager_port": 19012}
      ],
      "scaling_type": "fixed",
      "autoscaling": {
        "min_replicas": 1,
        "max_replicas": 3,
        "target_cpu_utilization": 80,
        "target_memory_enabled": false,
        "target_memory_utilization": 80
      },
      "health_check": $health_check
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

_health_check() {
  echo "{\"enabled\": $1, \"type\": \"$2\", \"path\": \"/health\", \"timeout_seconds\": 1, \"period_seconds\": 5, \"initial_delay_seconds\": 5}"
}

_render() {
  local ctx="$BATS_TEST_TMPDIR/ctx.json"
  _context "$1" > "$ctx"
  gomplate -c .="$ctx" -f "$DEPLOYMENT"
}

_probe_count() {
  local rendered="$1" container="$2"
  echo "$rendered" | yq -N ".spec.template.spec.containers[] | select(.name == \"$container\") | [.livenessProbe, .readinessProbe, .startupProbe] | map(select(. != null)) | length"
}

_assert_probes_on_every_container() {
  local rendered="$1" expected="$2"
  local container actual
  for container in http application http-8081 grpc-9012; do
    actual=$(_probe_count "$rendered" "$container")
    if [ "$actual" != "$expected" ]; then
      echo "container '$container': expected $expected probes, got $actual"
      return 1
    fi
  done
}

@test "health check disabled: no container gets liveness, readiness or startup probes" {
  rendered=$(_render "$(_health_check false HTTP)")

  _assert_probes_on_every_container "$rendered" 0
}

@test "health check disabled with TCP type: no container gets probes either" {
  rendered=$(_render "$(_health_check false TCP)")

  _assert_probes_on_every_container "$rendered" 0
}

@test "health check enabled: every container keeps its three probes" {
  rendered=$(_render "$(_health_check true HTTP)")

  _assert_probes_on_every_container "$rendered" 3
}

@test "scope predating the enabled flag: every container keeps its three probes" {
  rendered=$(_render '{"type": "HTTP", "path": "/health", "timeout_seconds": 1, "period_seconds": 5, "initial_delay_seconds": 5}')

  _assert_probes_on_every_container "$rendered" 3
}

@test "health check disabled: containers and their ports survive" {
  rendered=$(_render "$(_health_check false HTTP)")

  assert_equal "$(echo "$rendered" | yq -N '[.spec.template.spec.containers[].name] | join(",")')" \
    "http,http-8081,grpc-9012,application"
  assert_equal "$(echo "$rendered" | yq -N '[.spec.template.spec.containers[] | select(.name == "application") | .ports[].containerPort] | join(",")')" \
    "8080,8081,9012"
  assert_equal "$(echo "$rendered" | yq -N '.spec.template.spec.containers[] | select(.name == "http") | .ports[0].containerPort')" \
    "80"
}

@test "health check disabled: the application keeps its graceful shutdown hook" {
  rendered=$(_render "$(_health_check false HTTP)")

  assert_equal "$(echo "$rendered" | yq -N '.spec.template.spec.containers[] | select(.name == "application") | .lifecycle.preStop.exec.command | join(" ")')" \
    "/bin/sleep 16"
}
