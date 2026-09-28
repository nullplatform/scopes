#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/build_context - limit resolution
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  unset LIMIT
}

@test "no limit in the request and no LIMIT env leaves LIMIT empty" {
  export CONTEXT='{"arguments":{"application_id":1,"scope_id":9}}'
  source "$PROJECT_ROOT/k8s/instance/build_context"
  [ -z "$LIMIT" ]
}

@test "limit in the request is exported as LIMIT" {
  export CONTEXT='{"arguments":{"application_id":1,"scope_id":9,"limit":25}}'
  source "$PROJECT_ROOT/k8s/instance/build_context"
  [ "$LIMIT" = "25" ]
}

@test "array-valued limit takes the first element" {
  export CONTEXT='{"arguments":{"application_id":1,"scope_id":9,"limit":["7"]}}'
  source "$PROJECT_ROOT/k8s/instance/build_context"
  [ "$LIMIT" = "7" ]
}

@test "LIMIT env is used when the request has no limit" {
  export LIMIT=50
  export CONTEXT='{"arguments":{"application_id":1,"scope_id":9}}'
  source "$PROJECT_ROOT/k8s/instance/build_context"
  [ "$LIMIT" = "50" ]
}

@test "request limit wins over LIMIT env" {
  export LIMIT=50
  export CONTEXT='{"arguments":{"application_id":1,"scope_id":9,"limit":25}}'
  source "$PROJECT_ROOT/k8s/instance/build_context"
  [ "$LIMIT" = "25" ]
}

@test "non-numeric limit is ignored" {
  export CONTEXT='{"arguments":{"application_id":1,"scope_id":9,"limit":"all"}}'
  source "$PROJECT_ROOT/k8s/instance/build_context"
  [ -z "$LIMIT" ]
}
