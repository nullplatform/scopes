#!/usr/bin/env bats
# =============================================================================
# Unit tests for metric/build_context - metric parameter extraction
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$BATS_TEST_DIRNAME/../build_context"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export K8S_NAMESPACE="nullplatform"

  np() {
    case "$1" in
      scope)
        echo '{"nrn": "nrn:org=1:account=2:ns=3:app=4"}'
        ;;
      provider)
        echo '{
          "results": [{
            "attributes": {
              "server": {
                "url": "http://prometheus:9090"
              }
            }
          }]
        }'
        ;;
    esac
  }
  export -f np

  export CONTEXT='{
    "arguments": {
      "scope_id": "scope-123",
      "application_id": "app-456",
      "deployment_id": "deploy-789",
      "metric": "system.cpu_usage_percentage",
      "start_time": "2024-01-01T00:00:00Z",
      "end_time": "2024-01-01T01:00:00Z",
      "period": "60",
      "group_by": ["instance_id"]
    }
  }'
}

teardown() {
  unset CONTEXT K8S_NAMESPACE PROMETHEUS_URL PROM_URL
  unset SCOPE_ID APPLICATION_ID DEPLOYMENT_ID METRIC_NAME
  unset START_TIME END_TIME PERIOD GROUP_BY
  unset -f np
}

run_build_context() {
  source "$SCRIPT"
}

# =============================================================================
# Success flow
# =============================================================================
@test "metric/build_context: exports all parameters correctly" {
  run_build_context

  assert_equal "$SCOPE_ID" "scope-123"
  assert_equal "$APPLICATION_ID" "app-456"
  assert_equal "$DEPLOYMENT_ID" "deploy-789"
  assert_equal "$METRIC_NAME" "system.cpu_usage_percentage"
  assert_equal "$START_TIME" "2024-01-01T00:00:00Z"
  assert_equal "$END_TIME" "2024-01-01T01:00:00Z"
  assert_equal "$PERIOD" "60"
  assert_equal "$K8S_NAMESPACE" "nullplatform"
}

@test "metric/build_context: produces no stdout output" {
  run bash "$BATS_TEST_DIRNAME/../build_context"

  assert_equal "$status" "0"
  assert_equal "$output" ""
}

# =============================================================================
# Prometheus URL resolution
# =============================================================================
@test "metric/build_context: uses PROMETHEUS_URL env var when set" {
  export PROMETHEUS_URL="http://custom-prometheus:9090"

  run_build_context

  assert_equal "$PROM_URL" "http://custom-prometheus:9090"
}

@test "metric/build_context: fetches prometheus URL from provider when not set" {
  unset PROMETHEUS_URL

  run_build_context

  assert_equal "$PROM_URL" "http://prometheus:9090"
}

# =============================================================================
# Argument handling
# =============================================================================
@test "metric/build_context: handles array arguments (joins with comma)" {
  run_build_context

  assert_equal "$GROUP_BY" "instance_id"
}

@test "metric/build_context: handles multiple array values" {
  export CONTEXT='{
    "arguments": {
      "scope_id": "scope-123",
      "group_by": ["scope_id", "instance_id"]
    }
  }'

  run_build_context

  assert_equal "$GROUP_BY" "scope_id,instance_id"
}

@test "metric/build_context: handles minimal arguments" {
  export CONTEXT='{
    "arguments": {
      "scope_id": "scope-123"
    }
  }'

  run_build_context

  assert_equal "$SCOPE_ID" "scope-123"
  assert_not_empty "$PROM_URL"
}

# =============================================================================
# Validation errors
# =============================================================================
@test "metric/build_context: fails with full error block when prometheus not found" {
  unset PROMETHEUS_URL

  np() {
    case "$1" in
      scope) echo '{"nrn": "nrn:org=1:account=2:ns=3:app=4"}' ;;
      provider) echo '{"results": []}' ;;
    esac
  }
  export -f np

  run bash "$BATS_TEST_DIRNAME/../build_context"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ No Prometheus provider configured"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "metrics provider has not been linked"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Configure a Prometheus provider"
  assert_contains "$output" "Link the metrics provider"
}
