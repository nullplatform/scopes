#!/usr/bin/env bats
# =============================================================================
# Unit tests for metric/metric - Prometheus metric queries
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Required environment variables
  export PROM_URL="http://prometheus:9090"
  export APPLICATION_ID="app-123"
  export SCOPE_ID="scope-456"
  export DEPLOYMENT_ID="deploy-789"
  export METRIC_NAME="system.cpu_usage_percentage"
  export START_TIME="2024-01-01T00:00:00Z"
  export END_TIME="2024-01-01T01:00:00Z"
  export PERIOD="60"
  export GROUP_BY=""

  # Source the metric script to get functions
  # We need to extract functions without running the main logic
  eval "$(sed -n '/^get_metric_config()/,/^}/p' "$BATS_TEST_DIRNAME/../metric")"
  eval "$(sed -n '/^build_filters()/,/^}/p' "$BATS_TEST_DIRNAME/../metric")"
  eval "$(sed -n '/^build_query()/,/^}/p' "$BATS_TEST_DIRNAME/../metric")"
  eval "$(sed -n '/^urlencode()/,/^}/p' "$BATS_TEST_DIRNAME/../metric")"

  # Mock curl for Prometheus queries
  curl() {
    echo '{
      "status": "success",
      "data": {
        "resultType": "matrix",
        "result": [{
          "metric": {"scope_id": "scope-456"},
          "values": [[1704067200, "0.5"], [1704067260, "0.6"]]
        }]
      }
    }'
  }
  export -f curl
}

teardown() {
  unset PROM_URL
  unset APPLICATION_ID
  unset SCOPE_ID
  unset DEPLOYMENT_ID
  unset METRIC_NAME
  unset START_TIME
  unset END_TIME
  unset PERIOD
  unset GROUP_BY
  unset TIME_RANGE
  unset INTERVAL
  unset -f curl
  unset -f get_metric_config
  unset -f build_filters
  unset -f build_query
  unset -f urlencode
}

# =============================================================================
# get_metric_config tests
# =============================================================================
@test "metric: get_metric_config returns gauge percent for cpu_usage_percentage" {
  result=$(get_metric_config)

  assert_equal "$(echo $result | cut -d' ' -f1)" "gauge"
  assert_equal "$(echo $result | cut -d' ' -f2)" "percent"
}

@test "metric: get_metric_config returns gauge seconds for response_time" {
  export METRIC_NAME="http.response_time"

  result=$(get_metric_config)

  assert_equal "$(echo $result | cut -d' ' -f2)" "seconds"
}

@test "metric: get_metric_config returns gauge count_per_minute for rpm" {
  export METRIC_NAME="http.rpm"

  result=$(get_metric_config)

  assert_equal "$(echo $result | cut -d' ' -f2)" "count_per_minute"
}

@test "metric: get_metric_config returns gauge percent for error_rate" {
  export METRIC_NAME="http.error_rate"

  result=$(get_metric_config)

  assert_equal "$(echo $result | cut -d' ' -f2)" "percent"
}

@test "metric: get_metric_config returns gauge percent for memory_usage_percentage" {
  export METRIC_NAME="system.memory_usage_percentage"

  result=$(get_metric_config)

  assert_equal "$(echo $result | cut -d' ' -f2)" "percent"
}

@test "metric: get_metric_config returns gauge kilobytes for used_memory_kb" {
  export METRIC_NAME="system.used_memory_kb"

  result=$(get_metric_config)

  assert_equal "$(echo $result | cut -d' ' -f2)" "kilobytes"
}

@test "metric: get_metric_config returns gauge count for cronjob.execution_count" {
  export METRIC_NAME="cronjob.execution_count"

  result=$(get_metric_config)

  assert_equal "$(echo $result | cut -d' ' -f2)" "count"
}

@test "metric: get_metric_config returns gauge unknown for unrecognized metric" {
  export METRIC_NAME="unknown.metric"

  result=$(get_metric_config)

  assert_equal "$(echo $result | cut -d' ' -f2)" "unknown"
}

# =============================================================================
# build_filters tests
# =============================================================================
@test "metric: build_filters includes application_id" {
  result=$(build_filters)

  assert_contains "$result" 'application_id="app-123"'
}

@test "metric: build_filters includes scope_id" {
  result=$(build_filters)

  assert_contains "$result" 'scope_id="scope-456"'
}

@test "metric: build_filters includes deployment_id" {
  result=$(build_filters)

  assert_contains "$result" 'deployment_id="deploy-789"'
}

@test "metric: build_filters excludes null deployment_id" {
  export DEPLOYMENT_ID="null"

  result=$(build_filters)

  [[ "$result" != *"deployment_id"* ]]
}

@test "metric: build_filters handles empty deployment_id" {
  export DEPLOYMENT_ID=""

  result=$(build_filters)

  [[ "$result" != *"deployment_id"* ]]
}

@test "metric: build_filters builds comma-separated filters" {
  result=$(build_filters)

  # Should have commas between filters
  assert_contains "$result" ","
}

# =============================================================================
# build_query tests
# =============================================================================
@test "metric: build_query generates cpu_usage query" {
  filters=$(build_filters)
  query=$(build_query "system.cpu_usage_percentage" "$filters" "5m")

  assert_contains "$query" "nullplatform_system_cpu_usage_percentage"
  assert_contains "$query" "avg("
}

@test "metric: build_query generates memory_usage query" {
  filters=$(build_filters)
  query=$(build_query "system.memory_usage_percentage" "$filters" "5m")

  assert_contains "$query" "nullplatform_system_memory_usage_percentage"
}

@test "metric: build_query generates rpm query with rate" {
  filters=$(build_filters)
  query=$(build_query "http.rpm" "$filters" "5m")

  assert_contains "$query" "rate("
  assert_contains "$query" "* 60"
}

@test "metric: build_query generates error_rate query" {
  filters=$(build_filters)
  query=$(build_query "http.error_rate" "$filters" "5m")

  assert_contains "$query" 'quality="OK (2XX, 3XX)"'
  assert_contains "$query" "*100"
}

@test "metric: build_query generates response_time query" {
  filters=$(build_filters)
  query=$(build_query "http.response_time" "$filters" "5m")

  assert_contains "$query" "idelta("
  assert_contains "$query" "nullplatform_http_response_time"
}

@test "metric: build_query generates healthcheck_count query" {
  filters=$(build_filters)
  query=$(build_query "http.healthcheck_count" "$filters" "5m")

  assert_contains "$query" 'is_healthcheck="yes"'
}

@test "metric: build_query generates healthcheck_fail query" {
  filters=$(build_filters)
  query=$(build_query "http.healthcheck_fail" "$filters" "5m")

  assert_contains "$query" 'is_healthcheck="yes"'
  assert_contains "$query" 'quality="OK (2XX, 3XX)"'
}

@test "metric: build_query generates cronjob execution_count query" {
  filters=$(build_filters)
  query=$(build_query "cronjob.execution_count" "$filters" "5m")

  assert_contains "$query" "kube_job_status_succeeded"
  assert_contains "$query" "kube_job_status_failed"
  assert_contains "$query" "job-${SCOPE_ID}"
}

@test "metric: build_query generates cronjob success_count query" {
  filters=$(build_filters)
  query=$(build_query "cronjob.success_count" "$filters" "5m")

  assert_contains "$query" "kube_job_status_succeeded"
}

@test "metric: build_query generates cronjob failure_count query" {
  filters=$(build_filters)
  query=$(build_query "cronjob.failure_count" "$filters" "5m")

  assert_contains "$query" "kube_job_status_failed"
}

@test "metric: build_query includes group_by when set" {
  export GROUP_BY="instance_id"
  filters=$(build_filters)
  query=$(build_query "system.cpu_usage_percentage" "$filters" "5m")

  assert_contains "$query" "by (instance_id)"
}

@test "metric: build_query omits group_by when empty" {
  export GROUP_BY=""
  filters=$(build_filters)
  query=$(build_query "system.cpu_usage_percentage" "$filters" "5m")

  [[ "$query" != *"by ("* ]]
}

@test "metric: build_query handles empty array group_by" {
  export GROUP_BY="[]"
  filters=$(build_filters)
  query=$(build_query "system.cpu_usage_percentage" "$filters" "5m")

  [[ "$query" != *"by ("* ]]
}

@test "metric: build_query returns default query for unknown metric" {
  filters=$(build_filters)
  query=$(build_query "unknown.metric" "$filters" "5m")

  assert_contains "$query" "up{"
}

# =============================================================================
# urlencode tests
# =============================================================================
@test "metric: urlencode encodes special characters" {
  result=$(urlencode "foo bar")

  assert_equal "$result" "foo%20bar"
}

@test "metric: urlencode preserves alphanumeric characters" {
  result=$(urlencode "abc123")

  assert_equal "$result" "abc123"
}

@test "metric: urlencode encodes equals sign" {
  result=$(urlencode "key=value")

  assert_contains "$result" "%3d"
}

# =============================================================================
# Full script integration tests
# =============================================================================
@test "metric: returns empty results when METRIC_NAME is empty" {
  unset METRIC_NAME
  export METRIC_NAME=""

  run bash "$BATS_TEST_DIRNAME/../metric"

  [ "$status" -eq 1 ]
  result=$(echo "$output" | jq -r '.results')
  assert_equal "$result" "[]"
}

@test "metric: returns empty results when APPLICATION_ID is empty" {
  unset APPLICATION_ID
  export APPLICATION_ID=""

  run bash "$BATS_TEST_DIRNAME/../metric"

  [ "$status" -eq 1 ]
  result=$(echo "$output" | jq -r '.results')
  assert_equal "$result" "[]"
}

@test "metric: returns error when PROM_URL is empty" {
  unset PROM_URL
  export PROM_URL=""

  run bash "$BATS_TEST_DIRNAME/../metric"

  [ "$status" -eq 1 ]
  assert_contains "$output" "PROM_URL is required"
}

@test "metric: returns valid JSON response structure" {
  run bash "$BATS_TEST_DIRNAME/../metric"

  [ "$status" -eq 0 ]
  # Validate JSON structure
  metric=$(echo "$output" | jq -r '.metric')
  type=$(echo "$output" | jq -r '.type')
  period=$(echo "$output" | jq -r '.period_in_seconds')
  unit=$(echo "$output" | jq -r '.unit')
  results=$(echo "$output" | jq -r '.results')

  assert_equal "$metric" "system.cpu_usage_percentage"
  assert_equal "$type" "gauge"
  assert_not_empty "$unit"
  assert_not_empty "$results"
}
