#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export DEPLOYMENT="$PROJECT_ROOT/k8s/deployment/templates/deployment.yaml.tpl"
  export SERVICE="$PROJECT_ROOT/k8s/deployment/templates/service.yaml.tpl"
  export ISTIO_SERVICE="$PROJECT_ROOT/k8s/deployment/templates/istio/service.yaml.tpl"
  export GOLDEN_NGINX="$BATS_TEST_DIRNAME/fixtures/deployment-nginx.golden.yaml"
  export GOLDEN_SERVICE_NGINX="$BATS_TEST_DIRNAME/fixtures/service-nginx.golden.yaml"
  export GOLDEN_ISTIO_SERVICE_NGINX="$BATS_TEST_DIRNAME/fixtures/istio-service-nginx.golden.yaml"
}

find_guard_end() {
  local start="$1"
  awk -v start="$start" '
    NR < start { next }
    {
      line = $0
      opens = gsub(/{{-? *(if|range)[^}]*}}/, "&", line)
      closes = gsub(/{{-? *end *}}/, "&", line)
      depth += opens - closes
      if (depth == 0) { print NR; exit }
    }
  ' "$DEPLOYMENT"
}

block_after() {
  local anchor="$1"
  local anchor_line if_line else_line end_line rel
  anchor_line=$(grep -n -- "$anchor" "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$anchor_line" ] || return 1

  rel=$(tail -n "+$anchor_line" "$DEPLOYMENT" | grep -nE '\{\{-? *if ' | head -1 | cut -d: -f1)
  if_line=$((anchor_line + rel - 1))

  rel=$(tail -n "+$((if_line + 1))" "$DEPLOYMENT" | grep -nE '\{\{-? *else *\}\}' | head -1 | cut -d: -f1)
  else_line=$((if_line + rel))

  rel=$(tail -n "+$((else_line + 1))" "$DEPLOYMENT" | grep -nE '\{\{-? *end *\}\}' | head -1 | cut -d: -f1)
  end_line=$((else_line + rel))

  echo "$if_line $else_line $end_line"
}

value_between() {
  local from="$1" to="$2" pattern="$3"
  sed -n "${from},${to}p" "$DEPLOYMENT" | grep -oE "$pattern" | head -1 | grep -oE '[0-9]+'
}

@test "el contenedor http está condicionado al flag" {
  guard_line=$(grep -nF 'if not $istio' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$guard_line" ]
  guard_end=$(find_guard_end "$guard_line")
  [ -n "$guard_end" ]
  http_line=$(grep -n 'name: http$' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$http_line" ]
  [ "$http_line" -gt "$guard_line" ]
  [ "$http_line" -lt "$guard_end" ]
}

@test "los contenedores grpc también están condicionados" {
  guard_line=$(grep -nF 'if not $istio' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  guard_end=$(find_guard_end "$guard_line")
  grpc_line=$(grep -n 'name: grpc-{{ .port }}' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$grpc_line" ]
  [ "$guard_line" -lt "$grpc_line" ]
  [ "$grpc_line" -lt "$guard_end" ]
}

@test "el contenedor de la aplicación no está condicionado al flag" {
  guard_line=$(grep -nF 'if not $istio' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  guard_end=$(find_guard_end "$guard_line")
  [ -n "$guard_end" ]
  app_line=$(grep -n 'name: application' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$app_line" ]
  [ "$app_line" -gt "$guard_end" ]
}

@test "con nginx sobreviven las tres probes TCP del sidecar (traffic_port)" {
  count=$(grep -cF '"traffic_port" .main_traffic_manager_port' "$DEPLOYMENT")
  [ "$count" -eq 3 ]
}

@test "drenaje istio: preStop 15s y terminationGracePeriodSeconds 45s, con margen" {
  read -r if_l else_l end_l <<< "$(block_after 'preStop:')"
  [ -n "$end_l" ]
  istio_sleep=$(value_between "$if_l" "$else_l" "'[0-9]+'")

  read -r gif_l gelse_l gend_l <<< "$(block_after 'restartPolicy: Always')"
  [ -n "$gend_l" ]
  istio_grace=$(value_between "$gif_l" "$gelse_l" 'terminationGracePeriodSeconds: [0-9]+')

  [ "$istio_sleep" -eq 15 ]
  [ "$istio_grace" -eq 45 ]
  margin=$((istio_grace - istio_sleep))
  [ "$margin" -ge 10 ]
}

@test "drenaje nginx: preStop 16s y terminationGracePeriodSeconds 30s no cambiaron, con margen" {
  read -r if_l else_l end_l <<< "$(block_after 'preStop:')"
  nginx_sleep=$(value_between "$else_l" "$end_l" "'[0-9]+'")

  read -r gif_l gelse_l gend_l <<< "$(block_after 'restartPolicy: Always')"
  nginx_grace=$(value_between "$gelse_l" "$gend_l" 'terminationGracePeriodSeconds: [0-9]+')

  [ "$nginx_sleep" -eq 16 ]
  [ "$nginx_grace" -eq 30 ]
  margin=$((nginx_grace - nginx_sleep))
  [ "$margin" -ge 10 ]
}

_context() {
  local traffic_proxy_field=""
  if [ -n "${1:-}" ]; then
    traffic_proxy_field="  \"traffic_proxy\": \"$1\","
  fi
  cat <<CTXEOF
{
$traffic_proxy_field
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
CTXEOF
}

_render() {
  local traffic_proxy="$1"
  local ctx="$BATS_TEST_TMPDIR/ctx.json"
  _context "$traffic_proxy" > "$ctx"
  gomplate -c .="$ctx" -f "$DEPLOYMENT"
}

@test "render istio: el pod queda con un único contenedor, application" {
  run _render istio
  [ "$status" -eq 0 ]
  names=$(echo "$output" | grep -E '^ *- name: ' | sed -E 's/^ *- name:[[:space:]]*//')
  [ "$names" = "application" ]
}

@test "render istio: las probes de application apuntan a main_http_port, no al puerto del sidecar ausente" {
  run _render istio
  [ "$status" -eq 0 ]
  app=$(echo "$output" | awk '/- name: application/,0')

  if echo "$app" | grep -qE '(port|containerPort): 80($|[^0-9])'; then
    echo "application probe/port still points at the departed sidecar's port 80"
    return 1
  fi

  count=$(echo "$app" | grep -cE '^ *port: 8080$')
  [ "$count" -eq 3 ]
}

@test "render nginx: el golden fixture no cambió" {
  local ctx="$BATS_TEST_TMPDIR/golden-ctx.json"
  cat > "$ctx" <<'CTXEOF'
{
  "traffic_proxy": "nginx",
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
  "traffic_manager_config_map": "cm-scope-123",
  "replicas": 1,
  "parameters": {"results": []}
}
CTXEOF
  run gomplate -c .="$ctx" -f "$DEPLOYMENT"
  [ "$status" -eq 0 ]
  diff <(echo "$output") "$GOLDEN_NGINX"
}

_service_context() {
  local traffic_proxy_field=""
  if [ -n "${1:-}" ]; then
    traffic_proxy_field="  \"traffic_proxy\": \"$1\","
  fi
  cat <<CTXEOF
{
$traffic_proxy_field
  "account": {"id": "acc1", "slug": "acct"},
  "namespace": {"id": "ns1", "slug": "nsps"},
  "application": {"id": "app1", "slug": "appslug"},
  "scope": {
    "id": "scope-123",
    "slug": "scopeslug",
    "capabilities": {
      "additional_ports": [
        {"port": 9090, "type": "GRPC", "traffic_manager_port": 19090},
        {"port": 9091, "type": "HTTP", "traffic_manager_port": 19091}
      ],
      "health_check": {"path": "/health", "timeout_seconds": 1, "period_seconds": 5}
    }
  },
  "deployment": {"id": "deploy-456"},
  "k8s_namespace": "ns-test",
  "k8s_modifiers": {},
  "main_http_port": 8080,
  "main_traffic_manager_port": 80,
  "component": "app"
}
CTXEOF
}

_render_service() {
  local tpl="$1" traffic_proxy="$2"
  local ctx="$BATS_TEST_TMPDIR/svc-ctx.json"
  _service_context "$traffic_proxy" > "$ctx"
  gomplate -c .="$ctx" -f "$tpl"
}

@test "render default service (nginx): el golden fixture no cambió" {
  run _render_service "$SERVICE" nginx
  [ "$status" -eq 0 ]
  diff <(echo "$output") "$GOLDEN_SERVICE_NGINX"
}

@test "render default service (sin flag): igual al golden de nginx" {
  run _render_service "$SERVICE" ""
  [ "$status" -eq 0 ]
  diff <(echo "$output") "$GOLDEN_SERVICE_NGINX"
}

@test "render istio service (nginx): el golden fixture no cambió" {
  run _render_service "$ISTIO_SERVICE" nginx
  [ "$status" -eq 0 ]
  diff <(echo "$output") "$GOLDEN_ISTIO_SERVICE_NGINX"
}

@test "render istio service (sin flag): igual al golden de nginx" {
  run _render_service "$ISTIO_SERVICE" ""
  [ "$status" -eq 0 ]
  diff <(echo "$output") "$GOLDEN_ISTIO_SERVICE_NGINX"
}

@test "render default service (istio): todos los targetPort apuntan a la aplicación" {
  run _render_service "$SERVICE" istio
  [ "$status" -eq 0 ]
  target_ports=$(echo "$output" | grep -oE 'targetPort: [0-9]+' | cut -d' ' -f2 | sort -n | tr '\n' ' ')
  [ "$target_ports" = "8080 9090 9091 " ]
}

@test "render istio service (istio): el targetPort apunta a la aplicación" {
  run _render_service "$ISTIO_SERVICE" istio
  [ "$status" -eq 0 ]
  target_ports=$(echo "$output" | grep -oE 'targetPort: [0-9]+' | cut -d' ' -f2 | tr '\n' ' ')
  [ "$target_ports" = "8080 " ]
}
