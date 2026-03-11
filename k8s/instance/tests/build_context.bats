#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/build_context - instance parameter extraction
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$BATS_TEST_DIRNAME/../build_context"

  export CONTEXT='{
    "arguments": {
      "application_id": "app-123",
      "scope_id": "scope-456",
      "deployment_id": "deploy-789"
    }
  }'

  export LIMIT=10
}

teardown() {
  unset CONTEXT LIMIT APPLICATION_ID SCOPE_ID DEPLOYMENT_ID
}

# =============================================================================
# Success flow
# =============================================================================
@test "instance/build_context: exports all parameters correctly" {
  source "$SCRIPT"

  assert_equal "$APPLICATION_ID" "app-123"
  assert_equal "$SCOPE_ID" "scope-456"
  assert_equal "$DEPLOYMENT_ID" "deploy-789"
  assert_equal "$LIMIT" "10"
}

@test "instance/build_context: produces no stdout output" {
  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_equal "$output" ""
}

# =============================================================================
# Array argument handling
# =============================================================================
@test "instance/build_context: handles array arguments (takes first element)" {
  export CONTEXT='{
    "arguments": {
      "application_id": ["app-first", "app-second"],
      "scope_id": ["scope-first", "scope-second"],
      "deployment_id": ["deploy-first", "deploy-second"]
    }
  }'

  source "$SCRIPT"

  assert_equal "$APPLICATION_ID" "app-first"
  assert_equal "$SCOPE_ID" "scope-first"
  assert_equal "$DEPLOYMENT_ID" "deploy-first"
}

# =============================================================================
# Missing / null arguments
# =============================================================================
@test "instance/build_context: handles missing arguments" {
  export CONTEXT='{
    "arguments": {}
  }'

  source "$SCRIPT"

  assert_equal "$APPLICATION_ID" "null"
  assert_equal "$SCOPE_ID" "null"
  assert_equal "$DEPLOYMENT_ID" "null"
}

@test "instance/build_context: handles null arguments object" {
  export CONTEXT='{}'

  source "$SCRIPT"

  assert_empty "$APPLICATION_ID"
  assert_empty "$SCOPE_ID"
  assert_empty "$DEPLOYMENT_ID"
}

# =============================================================================
# LIMIT handling
# =============================================================================
@test "instance/build_context: uses default LIMIT of 10 when not set" {
  unset LIMIT

  source "$SCRIPT"

  assert_equal "$LIMIT" "10"
}

@test "instance/build_context: preserves custom LIMIT" {
  export LIMIT=50

  source "$SCRIPT"

  assert_equal "$LIMIT" "50"
}
