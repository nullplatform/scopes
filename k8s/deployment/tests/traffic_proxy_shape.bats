#!/usr/bin/env bats
# =============================================================================
# Tests estructurales del flag traffic_proxy en el template del deployment.
#
# Grep-based sobre el template, en la línea de traffic_manager_port_shape.bats.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export DEPLOYMENT="$PROJECT_ROOT/k8s/deployment/templates/deployment.yaml.tpl"
}

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

@test "con istio hay un preStop que reemplaza el drenaje del sidecar" {
  # start.sh del traffic-manager devolvía 503 durante GRACE_PERIOD para que el
  # balanceador sacara el pod. Sin sidecar, el preStop compra ese tiempo. Un
  # grep de 'preStop' a secas ya pasaba antes de tocar nada: el contenedor
  # application ya traía uno para nginx. Hay que buscar el sleep de istio.
  run grep -c 'sleep 15' "$DEPLOYMENT"
  [ "$output" -ge 1 ]
}

@test "con istio se define terminationGracePeriodSeconds" {
  # 'terminationGracePeriodSeconds' a secas ya existía (30, para nginx); lo
  # que hay que probar es que aparece el valor nuevo para istio.
  grep -qF 'terminationGracePeriodSeconds: 45' "$DEPLOYMENT"
}

@test "el preStop dura menos que el grace period" {
  # Si el sleep dura más, kubelet mata el pod en medio del drenaje.
  sleep_seconds=$(grep -A3 'preStop' "$DEPLOYMENT" | grep -oE 'sleep [0-9]+' | head -1 | grep -oE '[0-9]+')
  grace_seconds=$(grep -oE 'terminationGracePeriodSeconds: [0-9]+' "$DEPLOYMENT" | head -1 | grep -oE '[0-9]+')
  [ -n "$sleep_seconds" ]
  [ -n "$grace_seconds" ]
  [ "$sleep_seconds" -lt "$grace_seconds" ]
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

@test "con nginx el template no cambió: el sidecar sigue con sus tres probes" {
  count=$(grep -cF '"traffic_port" .main_traffic_manager_port' "$DEPLOYMENT")
  [ "$count" -eq 3 ]
}
