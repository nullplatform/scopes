#!/usr/bin/env bats
# =============================================================================
# Unit tests for log/build_context - log parameter extraction
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$BATS_TEST_DIRNAME/../build_context"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export NP_ACTION_CONTEXT='{
    "notification": {
      "arguments": {
        "scope_id": "scope-123",
        "application_id": "app-456",
        "deployment_id": "deploy-789",
        "next_page_token": "token-abc",
        "start_time": "1704067200000",
        "filter_pattern": "ERROR",
        "instance_id": "pod-xyz",
        "limit": "100"
      }
    }
  }'
}

teardown() {
  unset NP_ACTION_CONTEXT SCOPE_ID APPLICATION_ID DEPLOYMENT_ID
  unset NEXT_PAGE_TOKEN START_TIME FILTER_PATTERN INSTANCE_ID LIMIT
}

run_build_context() {
  source "$SCRIPT"
}

# =============================================================================
# Success flow
# =============================================================================
@test "log/build_context: exports all parameters correctly" {
  run_build_context

  assert_equal "$SCOPE_ID" "scope-123"
  assert_equal "$APPLICATION_ID" "app-456"
  assert_equal "$DEPLOYMENT_ID" "deploy-789"
  assert_equal "$NEXT_PAGE_TOKEN" "token-abc"
  assert_equal "$START_TIME" "1704067200000"
  assert_equal "$FILTER_PATTERN" "ERROR"
  assert_equal "$INSTANCE_ID" "pod-xyz"
  assert_equal "$LIMIT" "100"
}

@test "log/build_context: produces no stdout output" {
  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_equal "$output" ""
}

# =============================================================================
# deploy_id fallback
# =============================================================================
@test "log/build_context: extracts DEPLOYMENT_ID from deploy_id fallback" {
  export NP_ACTION_CONTEXT='{
    "notification": {
      "arguments": {
        "application_id": "app-456",
        "deploy_id": "deploy-fallback"
      }
    }
  }'

  run_build_context

  assert_equal "$DEPLOYMENT_ID" "deploy-fallback"
}

# =============================================================================
# Optional arguments
# =============================================================================
@test "log/build_context: handles missing optional arguments" {
  export NP_ACTION_CONTEXT='{
    "notification": {
      "arguments": {
        "application_id": "app-456"
      }
    }
  }'

  run_build_context

  assert_equal "$APPLICATION_ID" "app-456"
  assert_empty "$SCOPE_ID"
  assert_empty "$DEPLOYMENT_ID"
  assert_empty "$NEXT_PAGE_TOKEN"
  assert_empty "$START_TIME"
  assert_empty "$FILTER_PATTERN"
  assert_empty "$INSTANCE_ID"
  assert_empty "$LIMIT"
}

# =============================================================================
# Validation errors
# =============================================================================
@test "log/build_context: fails with full error block when APPLICATION_ID is missing" {
  export NP_ACTION_CONTEXT='{
    "notification": {
      "arguments": {
        "scope_id": "scope-123"
      }
    }
  }'

  run bash "$BATS_TEST_DIRNAME/../build_context"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ APPLICATION_ID is missing"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "application_id parameter"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "application_id in the request"
}

@test "log/build_context: fails with empty notification arguments" {
  export NP_ACTION_CONTEXT='{
    "notification": {
      "arguments": {}
    }
  }'

  run bash "$BATS_TEST_DIRNAME/../build_context"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ APPLICATION_ID is missing"
}
