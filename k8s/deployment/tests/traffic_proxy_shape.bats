#!/usr/bin/env bats
# =============================================================================
# Tests estructurales + de render del flag traffic_proxy en el template del
# deployment.
#
# La parte estructural es grep-based sobre el template, en la línea de
# traffic_manager_port_shape.bats. La parte de render usa gomplate de verdad
# contra el template, en la línea de grpc_port_shape.bats — necesaria porque
# ningún test grep-based puede confirmar qué contenedor queda de pie ni a qué
# puerto apuntan sus probes una vez que el template decide, en base al flag,
# qué se renderiza.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export DEPLOYMENT="$PROJECT_ROOT/k8s/deployment/templates/deployment.yaml.tpl"
  export GOLDEN_NGINX="$BATS_TEST_DIRNAME/fixtures/deployment-nginx.golden.yaml"
}

# -----------------------------------------------------------------------------
# Helpers estructurales
# -----------------------------------------------------------------------------

# Imprime la línea del {{- end }} que cierra el guard que arranca en la línea
# $1, contando la profundidad de if/range anidados. Un simple "primer {{- end
# }} después del guard" encuentra el end de un if anidado (p.ej. el de
# traffic_manager_config_map) en vez del que realmente cierra el guard.
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

# Imprime "if_line else_line end_line" del primer bloque {{- if }}/{{- else
# }}/{{- end }} que aparece después de la primera línea que matchea $1.
# Asume que ese bloque puntual no tiene ifs anidados propios (cierto para los
# dos guards de drenaje: el preStop de application y terminationGracePeriod-
# Seconds — cada uno es un if/else/end simple). Sirve para no repetir el
# error de "el primer valor de cada tipo en el archivo, sea cual sea su
# bloque", que es lo que hacía pasar estos tests por casualidad de orden.
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

# Primer número que matchea $3 (regex) dentro de las líneas [$1, $2] del
# template. Acotar el rango al bloque real (via block_after) es lo que hace
# que esto identifique el valor de una rama específica en vez de "el primero
# que aparece en el archivo".
value_between() {
  local from="$1" to="$2" pattern="$3"
  sed -n "${from},${to}p" "$DEPLOYMENT" | grep -oE "$pattern" | head -1 | grep -oE '[0-9]+'
}

# -----------------------------------------------------------------------------
# Estructurales — condicionamiento de contenedores
# -----------------------------------------------------------------------------

@test "el contenedor http está condicionado al flag" {
  # El contenedor http tiene que caer realmente dentro del rango que abarca
  # el guard, no solo aparecer en alguna línea posterior del archivo.
  guard_line=$(grep -n 'ne .traffic_proxy "istio"' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$guard_line" ]
  guard_end=$(find_guard_end "$guard_line")
  [ -n "$guard_end" ]
  http_line=$(grep -n 'name: http$' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$http_line" ]
  [ "$http_line" -gt "$guard_line" ]
  [ "$http_line" -lt "$guard_end" ]
}

@test "los contenedores grpc también están condicionados" {
  # Usan la misma imagen del traffic-manager: sin sidecar tampoco van.
  guard_line=$(grep -n 'ne .traffic_proxy "istio"' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  guard_end=$(find_guard_end "$guard_line")
  grpc_line=$(grep -n 'name: grpc-{{ .port }}' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$grpc_line" ]
  [ "$guard_line" -lt "$grpc_line" ]
  [ "$grpc_line" -lt "$guard_end" ]
}

@test "el contenedor de la aplicación no está condicionado al flag" {
  # Guarda contra un if mal cerrado que se lleve puesta la app: comprueba que
  # 'name: application' cae fuera del rango que abarca el guard, no solo que
  # la cadena aparezca en algún lado del archivo.
  guard_line=$(grep -n 'ne .traffic_proxy "istio"' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  guard_end=$(find_guard_end "$guard_line")
  [ -n "$guard_end" ]
  app_line=$(grep -n 'name: application' "$DEPLOYMENT" | head -1 | cut -d: -f1)
  [ -n "$app_line" ]
  [ "$app_line" -gt "$guard_end" ]
}

@test "con nginx sobreviven las tres probes TCP del sidecar (traffic_port)" {
  # Cobertura acotada: solo pin-ea que las tres llamadas a probe.tcp del
  # sidecar principal siguen usando main_traffic_manager_port. La garantía
  # amplia de "el render nginx no cambió" la da el test de golden fixture de
  # más abajo.
  count=$(grep -cF '"traffic_port" .main_traffic_manager_port' "$DEPLOYMENT")
  [ "$count" -eq 3 ]
}

# -----------------------------------------------------------------------------
# Estructurales — drenaje (preStop / terminationGracePeriodSeconds), ancladas
# al bloque real de cada rama, no al orden en que aparecen en el archivo.
# -----------------------------------------------------------------------------

@test "drenaje istio: preStop 15s y terminationGracePeriodSeconds 45s, con margen" {
  read -r if_l else_l end_l <<< "$(block_after 'preStop:')"
  [ -n "$end_l" ]
  istio_sleep=$(value_between "$if_l" "$else_l" "'[0-9]+'")

  read -r gif_l gelse_l gend_l <<< "$(block_after 'restartPolicy: Always')"
  [ -n "$gend_l" ]
  istio_grace=$(value_between "$gif_l" "$gelse_l" 'terminationGracePeriodSeconds: [0-9]+')

  [ "$istio_sleep" -eq 15 ]
  [ "$istio_grace" -eq 45 ]
  # Margen real, no un < a secas: un preStop de 44s contra un grace de 45s
  # pasaría un chequeo de "<" pero deja a kubelet un segundo de margen para
  # matar el pod en medio del drenaje.
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

# -----------------------------------------------------------------------------
# Render — gomplate real, en la línea de grpc_port_shape.bats. Necesario
# porque nada grep-based puede confirmar qué queda parado en el pod ni a qué
# puerto apuntan sus probes una vez resuelto el condicional.
# -----------------------------------------------------------------------------

# $1: valor de traffic_proxy a inyectar en el contexto, o "" para omitir la
# clave por completo (ejercita el default cuando el caller no la setea).
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

  # Nada en el contenedor application debe apuntar al puerto 80 (main_traffic_
  # manager_port): sin sidecar, ese puerto no lo escucha nadie y el pod
  # quedaría permanentemente unready. "8080" no debe confundirse con "80".
  if echo "$app" | grep -qE '(port|containerPort): 80($|[^0-9])'; then
    echo "application probe/port still points at the departed sidecar's port 80"
    return 1
  fi

  # Las tres probes (liveness/readiness/startup) sí deben apuntar al puerto
  # real de la app.
  count=$(echo "$app" | grep -cE '^ *port: 8080$')
  [ "$count" -eq 3 ]
}

@test "render nginx: el golden fixture no cambió" {
  # La garantía "el camino nginx no cambió" no puede vivir solo en un paso
  # manual (diff a mano contra HEAD~1); institucionalizada acá, cualquier
  # cambio futuro al render nginx —a propósito o no— tiene que tocar este
  # fixture a mano para que el test pase, lo cual es la señal que se busca:
  # los dos caminos conviven indefinidamente y el nginx no debe moverse salvo
  # decisión explícita.
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
