#!/usr/bin/env bats
# =============================================================================
# Unit tests for metric/list script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats azure-apps/metric/tests/scripts/list_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  AZURE_APPS_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$AZURE_APPS_DIR/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  SCRIPT_PATH="$PROJECT_DIR/list"
}

# =============================================================================
# Test: Full output structure
# =============================================================================
@test "Should produce valid JSON output" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local expected_json
  expected_json=$(cat <<'EOF'
{
  "results": [
    {
      "name": "http.rpm",
      "title": "Throughput",
      "unit": "rpm",
      "available_filters": ["scope_id"],
      "available_group_by": []
    },
    {
      "name": "http.response_time",
      "title": "Response time",
      "unit": "seconds",
      "available_filters": ["scope_id"],
      "available_group_by": []
    },
    {
      "name": "http.error_rate",
      "title": "Error rate",
      "unit": "%",
      "available_filters": ["scope_id"],
      "available_group_by": []
    },
    {
      "name": "http.request_count",
      "title": "Request count",
      "unit": "count",
      "available_filters": ["scope_id"],
      "available_group_by": []
    },
    {
      "name": "http.5xx_count",
      "title": "5xx errors",
      "unit": "count",
      "available_filters": ["scope_id"],
      "available_group_by": []
    },
    {
      "name": "http.4xx_count",
      "title": "4xx errors",
      "unit": "count",
      "available_filters": ["scope_id"],
      "available_group_by": []
    },
    {
      "name": "system.cpu_usage_percentage",
      "title": "CPU usage",
      "unit": "%",
      "available_filters": ["scope_id"],
      "available_group_by": []
    },
    {
      "name": "system.memory_usage_percentage",
      "title": "Memory usage percentage",
      "unit": "%",
      "available_filters": ["scope_id"],
      "available_group_by": []
    },
    {
      "name": "system.health_check_status",
      "title": "Health check status",
      "unit": "%",
      "available_filters": ["scope_id"],
      "available_group_by": []
    }
  ]
}
EOF
)

  assert_json_equal "$output" "$expected_json" "Metric list output"
}

# =============================================================================
# Test: Metric count
# =============================================================================
@test "Should include all 9 metrics in the catalog" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local count
  count=$(echo "$output" | jq '.results | length')
  assert_equal "$count" "9"
}

# =============================================================================
# Test: Filters
# =============================================================================
@test "Should set available_filters to scope_id for all metrics" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  # Check that all metrics have ["scope_id"] as available_filters
  local all_match
  all_match=$(echo "$output" | jq '[.results[] | .available_filters == ["scope_id"]] | all')
  assert_equal "$all_match" "true"
}

# =============================================================================
# Test: Group by
# =============================================================================
@test "Should set available_group_by to empty array for all metrics" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local all_empty
  all_empty=$(echo "$output" | jq '[.results[] | .available_group_by == []] | all')
  assert_equal "$all_empty" "true"
}

# =============================================================================
# Test: Individual metrics exist
# =============================================================================
@test "Should include http.rpm metric" {
  run source "$SCRIPT_PATH"

  local has_metric
  has_metric=$(echo "$output" | jq '[.results[] | select(.name == "http.rpm")] | length')
  assert_equal "$has_metric" "1"
}

@test "Should include http.error_rate metric" {
  run source "$SCRIPT_PATH"

  local has_metric
  has_metric=$(echo "$output" | jq '[.results[] | select(.name == "http.error_rate")] | length')
  assert_equal "$has_metric" "1"
}

@test "Should include system.cpu_usage_percentage metric" {
  run source "$SCRIPT_PATH"

  local has_metric
  has_metric=$(echo "$output" | jq '[.results[] | select(.name == "system.cpu_usage_percentage")] | length')
  assert_equal "$has_metric" "1"
}

@test "Should include system.health_check_status metric" {
  run source "$SCRIPT_PATH"

  local has_metric
  has_metric=$(echo "$output" | jq '[.results[] | select(.name == "system.health_check_status")] | length')
  assert_equal "$has_metric" "1"
}
