#!/usr/bin/env bats
# =============================================================================
# Unit tests for metric/list - list available metrics
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
}

# =============================================================================
# Full JSON structure validation
# =============================================================================
@test "metric/list: produces complete JSON with all expected metrics" {
  run bash "$BATS_TEST_DIRNAME/../list"

  assert_equal "$status" "0"

  local expected_json='{
    "results": [
      {
        "name": "http.rpm",
        "title": "Throughput",
        "unit": "rpm",
        "available_filters": ["scope_id", "instance_id"],
        "available_group_by": ["instance_id"]
      },
      {
        "name": "http.response_time",
        "title": "Response time",
        "unit": "ms",
        "available_filters": ["scope_id", "instance_id"],
        "available_group_by": ["instance_id"]
      },
      {
        "name": "http.error_rate",
        "title": "Error rate",
        "unit": "%",
        "available_filters": ["scope_id", "instance_id"],
        "available_group_by": ["instance_id"]
      },
      {
        "name": "system.cpu_usage_percentage",
        "title": "CPU usage",
        "unit": "%",
        "available_filters": ["scope_id", "instance_id"],
        "available_group_by": ["instance_id"]
      },
      {
        "name": "system.memory_usage_percentage",
        "title": "Memory usage percentage",
        "unit": "%",
        "available_filters": ["scope_id", "instance_id"],
        "available_group_by": ["scope_id", "instance_id"]
      },
      {
        "name": "system.used_memory_kb",
        "title": "Memory usage in kb",
        "unit": "kb",
        "available_filters": ["scope_id", "instance_id"],
        "available_group_by": ["scope_id", "instance_id"]
      },
      {
        "name": "http.healthcheck_count",
        "title": "Healthcheck",
        "unit": "check",
        "available_filters": ["scope_id", "instance_id"],
        "available_group_by": ["instance_id"]
      }
    ]
  }'

  assert_json_equal "$output" "$expected_json" "Complete metric list output"
}
