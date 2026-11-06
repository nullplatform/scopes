#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  eval "$(sed -n '/^build_istio_healthcheck_query()/,/^}/p;/^build_query()/,/^}/p' "$PROJECT_ROOT/k8s/metric/metric")"
  export GROUP_BY=""
}

teardown() {
  unset TRAFFIC_PROXY GROUP_BY 2>/dev/null || true
}

@test "healthcheck_count con nginx: cuenta los access logs de los probes" {
  export TRAFFIC_PROXY=nginx
  run build_query "http.healthcheck_count" 'scope_id="1"' "5m"
  assert_contains "$output" "nullplatform_http_response_time_count"
  assert_contains "$output" 'is_healthcheck="yes"'
}

@test "healthcheck_count con istio: usa el readiness del pod" {
  export TRAFFIC_PROXY=istio
  run build_query "http.healthcheck_count" 'scope_id="1"' "5m"
  [ "$output" = 'sum(nullplatform_healthcheck_status{scope_id="1"})' ]
}

@test "healthcheck_fail con nginx: resta los probes OK del total" {
  export TRAFFIC_PROXY=nginx
  run build_query "http.healthcheck_fail" 'scope_id="1"' "5m"
  assert_contains "$output" 'quality="OK (2XX, 3XX)"'
  assert_contains "$output" 'is_healthcheck="yes"'
}

@test "healthcheck_fail con istio: usa la métrica dedicada" {
  export TRAFFIC_PROXY=istio
  run build_query "http.healthcheck_fail" 'scope_id="1"' "5m"
  [ "$output" = 'sum(nullplatform_healthcheck_fail{scope_id="1"})' ]
}

@test "healthcheck sin el flag: se comporta como nginx" {
  unset TRAFFIC_PROXY
  run build_query "http.healthcheck_count" 'scope_id="1"' "5m"
  assert_contains "$output" 'is_healthcheck="yes"'
}

@test "healthcheck con istio y groupBy agrupa por las dimensiones pedidas" {
  export TRAFFIC_PROXY=istio
  export GROUP_BY="scope_id"
  run build_query "http.healthcheck_count" 'scope_id="1"' "5m"
  [ "$output" = 'sum(nullplatform_healthcheck_status{scope_id="1"}) by (scope_id)' ]
  run build_query "http.healthcheck_fail" 'scope_id="1"' "5m"
  [ "$output" = 'sum(nullplatform_healthcheck_fail{scope_id="1"}) by (scope_id)' ]
}

@test "las métricas de tráfico no dependen del flag" {
  for metric in http.rpm http.error_rate http.response_time; do
    export TRAFFIC_PROXY=nginx
    nginx_query=$(build_query "$metric" 'scope_id="1"' "5m")
    export TRAFFIC_PROXY=istio
    istio_query=$(build_query "$metric" 'scope_id="1"' "5m")
    [ -n "$nginx_query" ] || false
    [ "$nginx_query" = "$istio_query" ] || false
  done
}
