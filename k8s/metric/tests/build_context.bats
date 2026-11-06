#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export PROMETHEUS_URL="http://prometheus:9090"
  export NP_LOG="$BATS_TEST_TMPDIR/np.log"
  export SCOPE_CONFIG_ATTRIBUTES='{}'
  unset TRAFFIC_PROXY
  : > "$NP_LOG"

  np() {
    echo "$*" >> "$NP_LOG"
    if [ "$1" = "scope" ] && [ "$2" = "read" ]; then
      echo '{"nrn":"organization=1:account=2:namespace=3:application=4:scope=5"}'
      return 0
    fi
    if [ "$1" = "provider" ] && [ "$2" = "list" ] && [ "$4" = "scope-configurations" ]; then
      echo "{\"results\":[{\"attributes\":$SCOPE_CONFIG_ATTRIBUTES}]}"
      return 0
    fi
    return 1
  }
  export -f np
}

_context() {
  echo "{\"arguments\":{\"scope_id\":\"5\",\"application_id\":\"4\",\"metric\":\"$1\"}}"
}

_resolved_traffic_proxy() {
  CONTEXT="$(_context "$1")" bash -c 'source "$SERVICE_PATH/metric/build_context" && echo "TRAFFIC_PROXY=$TRAFFIC_PROXY"'
}

@test "healthcheck: sin configuración el flag es nginx" {
  run _resolved_traffic_proxy http.healthcheck_count
  [ "$status" -eq 0 ]
  assert_contains "$output" "TRAFFIC_PROXY=nginx"
}

@test "healthcheck: toma el flag del provider scope-configurations" {
  export SCOPE_CONFIG_ATTRIBUTES='{"deployment":{"traffic_proxy":"istio"}}'
  run _resolved_traffic_proxy http.healthcheck_fail
  [ "$status" -eq 0 ]
  assert_contains "$output" "TRAFFIC_PROXY=istio"
}

@test "healthcheck: toma el flag del entorno cuando el provider no lo define" {
  export TRAFFIC_PROXY=istio
  run _resolved_traffic_proxy http.healthcheck_count
  [ "$status" -eq 0 ]
  assert_contains "$output" "TRAFFIC_PROXY=istio"
}

@test "healthcheck: el provider gana sobre el entorno, igual que en el deployment" {
  export TRAFFIC_PROXY=nginx
  export SCOPE_CONFIG_ATTRIBUTES='{"deployment":{"traffic_proxy":"istio"}}'
  run _resolved_traffic_proxy http.healthcheck_count
  [ "$status" -eq 0 ]
  assert_contains "$output" "TRAFFIC_PROXY=istio"
}

@test "healthcheck: un valor desconocido aborta" {
  export SCOPE_CONFIG_ATTRIBUTES='{"deployment":{"traffic_proxy":"envoy"}}'
  run _resolved_traffic_proxy http.healthcheck_count
  [ "$status" -ne 0 ]
  assert_contains "$output" "TRAFFIC_PROXY must be 'nginx' or 'istio'"
}

@test "healthcheck: si falla la consulta del provider aborta en vez de asumir nginx" {
  np() {
    if [ "$1" = "scope" ]; then echo '{"nrn":"n"}'; return 0; fi
    return 1
  }
  export -f np
  run _resolved_traffic_proxy http.healthcheck_count
  [ "$status" -ne 0 ]
  [[ "$output" != *"TRAFFIC_PROXY="* ]]
}

@test "otras métricas no consultan el provider scope-configurations" {
  run _resolved_traffic_proxy http.rpm
  [ "$status" -eq 0 ]
  run grep -c 'scope-configurations' "$NP_LOG"
  [ "$output" = "0" ]
}

@test "healthcheck: si falla la lectura del scope aborta en vez de asumir nginx" {
  np() {
    echo "$*" >> "$NP_LOG"
    return 1
  }
  export -f np
  run _resolved_traffic_proxy http.healthcheck_count
  [ "$status" -ne 0 ]
  [[ "$output" != *"TRAFFIC_PROXY="* ]] || false
  run grep -c 'scope-configurations' "$NP_LOG"
  [ "$output" = "0" ]
}

@test "healthcheck sin PROMETHEUS_URL: lee el scope una sola vez" {
  unset PROMETHEUS_URL
  np() {
    echo "$*" >> "$NP_LOG"
    if [ "$1" = "scope" ]; then echo '{"nrn":"n"}'; return 0; fi
    if [ "$4" = "metrics" ]; then echo '{"results":[{"attributes":{"server":{"url":"http://p"}}}]}'; return 0; fi
    if [ "$4" = "scope-configurations" ]; then echo '{"results":[{"attributes":{}}]}'; return 0; fi
    return 1
  }
  export -f np
  run _resolved_traffic_proxy http.healthcheck_count
  [ "$status" -eq 0 ]
  run grep -c '^scope read' "$NP_LOG"
  [ "$output" = "1" ]
}
