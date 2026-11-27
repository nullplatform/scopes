#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PROJECT_ROOT/k8s/metric/metric"
  export BUILD_CONTEXT="$PROJECT_ROOT/k8s/metric/build_context"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/curl" << 'STUB'
#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    query=*) echo "${arg#query=}" >> "$CURL_LOG" ;;
  esac
done
echo '{"status":"success","data":{"result":[{"metric":{"traffic":"internal"},"values":[[1795800000,"1.5"]]}]}}'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export PROM_URL="http://prometheus"
  export APPLICATION_ID="10"
  export SCOPE_ID="20"
  export TIME_RANGE="1h"
  export INTERVAL="5m"
  unset TRAFFIC GROUP_BY DEPLOYMENT_ID
}

query() {
  cat "$CURL_LOG"
}

@test "http.rpm without traffic: query unchanged" {
  export METRIC_NAME="http.rpm"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_equal "$(query)" 'sum(rate(nullplatform_http_response_time_count{application_id="10",scope_id="20"}[5m])) * 60'
}

@test "http.rpm with traffic=internal filters on the label" {
  export METRIC_NAME="http.rpm" TRAFFIC="internal"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_equal "$(query)" 'sum(rate(nullplatform_http_response_time_count{application_id="10",scope_id="20",traffic="internal"}[5m])) * 60'
}

@test "http.error_rate with traffic=external filters both terms" {
  export METRIC_NAME="http.error_rate" TRAFFIC="external"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_contains "$(query)" 'nullplatform_http_response_time_count{application_id="10",scope_id="20",traffic="external"}'
  assert_contains "$(query)" '{application_id="10",scope_id="20",traffic="external",quality="OK (2XX, 3XX)"}'
}

@test "http.response_time grouped by traffic returns the label as selector" {
  export METRIC_NAME="http.response_time" GROUP_BY="traffic"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_contains "$(query)" ') by (traffic)/sum('
  assert_equal "$(echo "$output" | jq -c '.results[0].selector')" '{"traffic":"internal"}'
}

@test "traffic is ignored for system and healthcheck metrics" {
  export TRAFFIC="internal"
  for m in system.cpu_usage_percentage http.healthcheck_count; do
    METRIC_NAME="$m" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
  done
  [[ "$(query)" != *traffic* ]]
}

@test "invalid traffic value fails without querying" {
  export METRIC_NAME="http.rpm" TRAFFIC='internal"}) or vector(1'
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  assert_contains "$output" "traffic must be internal or external"
  [ ! -s "$CURL_LOG" ]
}

@test "build_context reads traffic from arguments.filters" {
  export PROMETHEUS_URL="http://prometheus"
  export CONTEXT='{"arguments":{"scope_id":"20","metric":"http.rpm","filters":{"traffic":"internal"},"group_by":["traffic"]}}'
  source "$BUILD_CONTEXT"
  assert_equal "$TRAFFIC" "internal"
  assert_equal "$GROUP_BY" "traffic"
}

@test "build_context reads traffic from a plain argument" {
  export PROMETHEUS_URL="http://prometheus"
  export CONTEXT='{"arguments":{"scope_id":"20","metric":"http.rpm","traffic":"external"}}'
  source "$BUILD_CONTEXT"
  assert_equal "$TRAFFIC" "external"
}

@test "build_context without traffic leaves it empty" {
  export PROMETHEUS_URL="http://prometheus"
  export CONTEXT='{"arguments":{"scope_id":"20","metric":"http.rpm"}}'
  source "$BUILD_CONTEXT"
  assert_empty "$TRAFFIC"
}
