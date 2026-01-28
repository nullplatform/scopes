#!/usr/bin/env bats
# =============================================================================
# Unit tests for metric/metric script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats azure-apps/metric/tests/scripts/metric_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  AZURE_APPS_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$AZURE_APPS_DIR/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  SCRIPT_PATH="$PROJECT_DIR/metric"
  MOCKS_DIR="$AZURE_APPS_DIR/deployment/tests/resources/mocks"
  RESPONSES_DIR="$MOCKS_DIR/responses"

  # Add mocks to PATH
  export PATH="$MOCKS_DIR:$PATH"

  # Set env vars (normally set by build_context)
  export METRIC_NAME="system.cpu_usage_percentage"
  export START_TIME="2026-01-27T00:00:00Z"
  export END_TIME="2026-01-27T01:00:00Z"
  export INTERVAL="5"
  export AZURE_RESOURCE_ID="/subscriptions/test-subscription-id/resourceGroups/test-resource-group/providers/Microsoft.Web/sites/tools-automation-development-tools-7"
  export AZURE_ACCESS_TOKEN="mock-azure-token"

  # Configure curl mock for Azure Monitor metrics
  export CURL_CALL_LOG=$(mktemp)
  export CURL_MOCK_EXIT_CODE=0
}

teardown() {
  rm -f "$CURL_CALL_LOG"
}

# =============================================================================
# Test: Output structure
# =============================================================================
@test "Should produce valid JSON output with correct structure" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  # Validate JSON structure
  local metric
  metric=$(echo "$output" | jq -r '.metric')
  assert_equal "$metric" "system.cpu_usage_percentage"

  local type
  type=$(echo "$output" | jq -r '.type')
  assert_equal "$type" "gauge"

  local period
  period=$(echo "$output" | jq '.period_in_seconds')
  assert_equal "$period" "300"

  local unit
  unit=$(echo "$output" | jq -r '.unit')
  assert_equal "$unit" "percent"

  local has_results
  has_results=$(echo "$output" | jq 'has("results")')
  assert_equal "$has_results" "true"
}

# =============================================================================
# Test: Metric mapping
# =============================================================================
@test "Should map system.cpu_usage_percentage to CpuPercentage" {
  export METRIC_NAME="system.cpu_usage_percentage"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=CpuPercentage"
}

@test "Should map system.memory_usage_percentage to MemoryPercentage" {
  export METRIC_NAME="system.memory_usage_percentage"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=MemoryPercentage"
}

@test "Should map http.response_time to HttpResponseTime" {
  export METRIC_NAME="http.response_time"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=HttpResponseTime"
}

@test "Should map http.request_count to Requests" {
  export METRIC_NAME="http.request_count"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=Requests"
}

@test "Should map http.5xx_count to Http5xx" {
  export METRIC_NAME="http.5xx_count"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=Http5xx"
}

@test "Should map http.4xx_count to Http4xx" {
  export METRIC_NAME="http.4xx_count"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=Http4xx"
}

@test "Should map system.health_check_status to HealthCheckStatus" {
  export METRIC_NAME="system.health_check_status"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=HealthCheckStatus"
}

# =============================================================================
# Test: Azure Monitor REST API call parameters
# =============================================================================
@test "Should call Azure Monitor REST API with correct resource" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "microsoft.insights/metrics"
}

@test "Should call Azure Monitor REST API with correct time range" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "timespan=2026-01-27T00:00:00Z/2026-01-27T01:00:00Z"
}

@test "Should call Azure Monitor REST API with correct interval" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "interval=PT5M"
}

# =============================================================================
# Test: Special cases
# =============================================================================
@test "Should compute http.rpm from Requests total divided by interval_minutes" {
  export METRIC_NAME="http.rpm"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=Requests"
  assert_contains "$calls" "aggregation=Total"
}

@test "Should compute http.error_rate from Http5xx and Requests" {
  export METRIC_NAME="http.error_rate"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local calls
  calls=$(cat "$CURL_CALL_LOG")
  assert_contains "$calls" "metricnames=Http5xx"
}

# =============================================================================
# Test: Validation
# =============================================================================
@test "Should fail for unknown metric name" {
  export METRIC_NAME="unknown.metric"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Unknown metric: unknown.metric"
}

@test "Should fail when METRIC_NAME is empty" {
  export METRIC_NAME=""

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
}
