#!/usr/bin/env bats
# The metric step serves Prometheus and Datadog from one image: build_context
# classifies the organization's metrics provider and exports the source the
# metric and list scripts dispatch on.

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export BUILD_CONTEXT="$PROJECT_ROOT/k8s/metric/build_context"
  export CONTEXT='{"arguments":{"scope_id":"1234","metric":"http.rpm","application_id":"42"}}'

  # A fake np on PATH: `scope read` answers with a fixed NRN, `provider list`
  # with whatever NP_PROVIDERS holds, and every call is logged.
  export NP_CALLS_LOG="$BATS_TEST_TMPDIR/np_calls.log"
  export NP_PROVIDERS='{"results":[]}'
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/np" <<'NP'
#!/bin/bash
echo "$*" >> "$NP_CALLS_LOG"
case "$1 $2" in
  "scope read") echo '{"id":1234,"nrn":"organization=1:account=2:namespace=3:application=4"}' ;;
  "provider list") echo "$NP_PROVIDERS" ;;
  *) echo "unexpected np call: $*" >&2; exit 1 ;;
esac
NP
  chmod +x "$BATS_TEST_TMPDIR/bin/np"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  unset METRICS_SOURCE METRICS_SOURCE_REQUIRED PROMETHEUS_URL PROM_URL \
    DATADOG_API_KEY DATADOG_APP_KEY DATADOG_SITE
}

DATADOG_PROVIDER='{"id":"p1","attributes":{"credentials":{"api_key":"dd-api","app_key":"dd-app"},"settings":{"site":"datadoghq.eu"}}}'
PROMETHEUS_PROVIDER='{"id":"p2","attributes":{"server":{"url":"http://prometheus.monitoring:9090"}}}'

# Sources build_context the way the workflow does and prints the exported
# source and its settings, so a test asserts on one line.
resolved() {
  bash -c "source \"$BUILD_CONTEXT\" && echo \"\$METRICS_SOURCE|\$PROM_URL|\$DATADOG_API_KEY|\$DATADOG_APP_KEY|\$DATADOG_SITE|\$METRIC_NAME|\$APPLICATION_ID\""
}

@test "a Datadog provider makes the source datadog with its keys and site" {
  export NP_PROVIDERS="{\"results\":[$DATADOG_PROVIDER]}"
  run resolved
  assert_equal "$status" 0
  assert_equal "$output" "datadog||dd-api|dd-app|datadoghq.eu|http.rpm|42"
}

@test "the scope id is taken from the enriched parameters when the arguments lack it, as metric:list sends it" {
  export NP_PROVIDERS="{\"results\":[$DATADOG_PROVIDER]}"
  export CONTEXT='{"arguments":{"application_id":"42"},"parameters":{"scope_id":"5678"},"tags":{"scope_id":"ignored-when-parameters-has-it"}}'
  export METRICS_SOURCE_REQUIRED=false
  run resolved
  assert_equal "$status" 0
  assert_contains "$output" "datadog||dd-api|dd-app|datadoghq.eu"
  assert_contains "$(cat "$NP_CALLS_LOG")" "scope read --id 5678"
}

@test "a null scope id exported by the entrypoint is not sent to the platform" {
  export CONTEXT='{"arguments":{"application_id":"42"},"parameters":{"scope_id":null}}'
  export METRICS_SOURCE_REQUIRED=false
  run resolved
  assert_equal "$status" 0
  assert_contains "$output" "prometheus|||||"
  [ ! -f "$NP_CALLS_LOG" ]
}

@test "a Prometheus provider makes the source prometheus with its url" {
  export NP_PROVIDERS="{\"results\":[$PROMETHEUS_PROVIDER]}"
  run resolved
  assert_equal "$status" 0
  assert_equal "$output" "prometheus|http://prometheus.monitoring:9090||||http.rpm|42"
}

@test "a Datadog provider without a site defaults to datadoghq.com" {
  export NP_PROVIDERS='{"results":[{"attributes":{"credentials":{"api_key":"dd-api","app_key":"dd-app"}}}]}'
  run resolved
  assert_equal "$status" 0
  assert_contains "$output" "datadog||dd-api|dd-app|datadoghq.com"
}

@test "the provider is looked up by the scope's nrn in the metrics category" {
  export NP_PROVIDERS="{\"results\":[$PROMETHEUS_PROVIDER]}"
  run resolved
  assert_equal "$status" 0
  assert_contains "$(cat "$NP_CALLS_LOG")" "scope read --id 1234"
  assert_contains "$(cat "$NP_CALLS_LOG")" "provider list --categories metrics --nrn organization=1:account=2:namespace=3:application=4"
}

@test "with both providers configured the first classifiable one wins" {
  export NP_PROVIDERS="{\"results\":[$DATADOG_PROVIDER,$PROMETHEUS_PROVIDER]}"
  run resolved
  assert_equal "$status" 0
  assert_contains "$output" "datadog||dd-api"
}

@test "METRICS_SOURCE picks that source among several providers" {
  export NP_PROVIDERS="{\"results\":[$DATADOG_PROVIDER,$PROMETHEUS_PROVIDER]}"
  export METRICS_SOURCE=prometheus
  run resolved
  assert_equal "$status" 0
  assert_equal "$output" "prometheus|http://prometheus.monitoring:9090||||http.rpm|42"
}

@test "a provider of an unknown shape is ignored" {
  export NP_PROVIDERS='{"results":[{"attributes":{"something":"else"}}]}'
  run resolved
  assert_equal "$status" 1
  assert_contains "$output" "There is no metrics provider configured"
}

@test "querying a metric without a provider fails with the message the UI shows" {
  run resolved
  assert_equal "$status" 1
  assert_contains "$output" "There is no metrics provider configured. Please configure Prometheus or Datadog in Platform settings and try again."
}

@test "listing metrics without a provider falls back to prometheus" {
  export METRICS_SOURCE_REQUIRED=false
  run resolved
  assert_equal "$status" 0
  assert_contains "$output" "prometheus|||||http.rpm|42"
}

@test "a Datadog provider without an app key is refused" {
  export NP_PROVIDERS='{"results":[{"attributes":{"credentials":{"api_key":"dd-api"}}}]}'
  run resolved
  assert_equal "$status" 1
  assert_contains "$output" "Datadog App Key is required"
}

@test "PROMETHEUS_URL in the environment stands in for a provider and skips the platform" {
  export PROMETHEUS_URL="http://localhost:9090"
  run resolved
  assert_equal "$status" 0
  assert_contains "$output" "prometheus|http://localhost:9090|"
  [ ! -f "$NP_CALLS_LOG" ]
}

@test "Datadog keys in the environment stand in for a provider and skip the platform" {
  export DATADOG_API_KEY="env-api" DATADOG_APP_KEY="env-app"
  run resolved
  assert_equal "$status" 0
  assert_contains "$output" "datadog||env-api|env-app|datadoghq.com"
  [ ! -f "$NP_CALLS_LOG" ]
}

@test "an unknown METRICS_SOURCE is refused" {
  export METRICS_SOURCE=cloudwatch
  export NP_PROVIDERS="{\"results\":[$PROMETHEUS_PROVIDER]}"
  run resolved
  assert_equal "$status" 1
  assert_contains "$output" "Unknown metrics source 'cloudwatch'"
}

@test "the metric script runs the resolved source's implementation" {
  # Without keys or url, each implementation is the one that reports what it
  # is missing, which proves the dispatch reached it.
  export METRIC_NAME=http.rpm APPLICATION_ID=42
  export METRICS_SOURCE=datadog
  run bash "$SERVICE_PATH/metric/metric"
  assert_equal "$status" 1
  assert_contains "$output" "DATADOG_API_KEY is required"

  export METRICS_SOURCE=prometheus
  run bash "$SERVICE_PATH/metric/metric"
  assert_equal "$status" 1
  assert_contains "$output" "PROM_URL is required"
}

@test "the list script lists the resolved source's metrics" {
  export METRICS_SOURCE=datadog
  run bash "$SERVICE_PATH/metric/list"
  assert_equal "$status" 0
  assert_contains "$output" '"http.healthcheck_fail"'

  export METRICS_SOURCE=prometheus
  run bash "$SERVICE_PATH/metric/list"
  assert_equal "$status" 0
  assert_contains "$output" '"system.used_memory_kb"'
}

@test "metric and list refuse to run before build_context resolved a source" {
  run bash "$SERVICE_PATH/metric/metric"
  assert_equal "$status" 1
  assert_contains "$output" "build_context must run first"
  run bash "$SERVICE_PATH/metric/list"
  assert_equal "$status" 1
  assert_contains "$output" "build_context must run first"
}

@test "metric and list only source the two known implementations" {
  export METRICS_SOURCE="../../../etc"
  run bash "$SERVICE_PATH/metric/metric"
  assert_equal "$status" 1
  assert_contains "$output" "METRICS_SOURCE must be prometheus or datadog"
  run bash "$SERVICE_PATH/metric/list"
  assert_equal "$status" 1
  assert_contains "$output" "METRICS_SOURCE must be prometheus or datadog"
}

@test "command arguments become upper-case variables without being evaluated" {
  export NP_PROVIDERS="{\"results\":[$PROMETHEUS_PROVIDER]}"
  export CONTEXT='{"arguments":{"scope_id":"1234","metric":"http.rpm","group_by":["scope_id","instance_id"],"time_range":"$(touch /tmp/pwned); echo injected"}}'
  run bash -c "source \"$BUILD_CONTEXT\" && echo \"\$GROUP_BY|\$TIME_RANGE\""
  assert_equal "$status" 0
  assert_equal "$output" 'scope_id,instance_id|$(touch /tmp/pwned); echo injected'
}

@test "command arguments can not retarget the source, its url, site or keys" {
  export NP_PROVIDERS="{\"results\":[$DATADOG_PROVIDER]}"
  export CONTEXT='{"arguments":{"scope_id":"1234","metric":"http.rpm","metrics_source":"../evil","datadog_site":"attacker.example.com","datadog_api_key":"stolen","prom_url":"http://attacker.example.com"}}'
  run resolved
  assert_equal "$status" 0
  assert_equal "$output" "datadog||dd-api|dd-app|datadoghq.eu|http.rpm|"
}
