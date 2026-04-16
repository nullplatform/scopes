#!/usr/bin/env bats
# =============================================================================
# Unit tests for service/scope/entrypoint - --no-params flag behavior
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCOPE_ID="scope-123"
  export SERVICE_PATH="/tmp/test-service-path"
  export OVERRIDES_PATH=""

  mkdir -p "$SERVICE_PATH/scope/workflows"
  touch "$SERVICE_PATH/scope/workflows/create.yaml"
  touch "$SERVICE_PATH/scope/workflows/update.yaml"
  touch "$SERVICE_PATH/scope/workflows/delete.yaml"
  touch "$SERVICE_PATH/scope/workflows/diagnose.yaml"
  touch "$SERVICE_PATH/scope/workflows/restart-pods.yaml"
  touch "$SERVICE_PATH/scope/workflows/pause-autoscaling.yaml"
  touch "$SERVICE_PATH/scope/workflows/resume-autoscaling.yaml"
  touch "$SERVICE_PATH/scope/workflows/set-desired-instance-count.yaml"

  export NP_HELP_SUPPORTS_NO_PARAMS="true"
}

teardown() {
  rm -rf "$SERVICE_PATH"
  unset -f np
}

mock_np() {
  np() {
    if [[ "$*" == *"--help"* ]]; then
      if [ "$NP_HELP_SUPPORTS_NO_PARAMS" = "true" ]; then
        echo "  --no-params    Skip parameter fetching"
      fi
      return 0
    fi
    export NP_EXECUTED_CMD="np $*"
    return 0
  }
  export -f np
}

# =============================================================================
# All scope actions SHOULD include --no-params (when CLI supports it)
# =============================================================================

@test "scope entrypoint: create includes --no-params" {
  mock_np
  export SERVICE_ACTION="create-scope"
  export SERVICE_ACTION_TYPE="create"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

@test "scope entrypoint: update includes --no-params" {
  mock_np
  export SERVICE_ACTION="update-scope"
  export SERVICE_ACTION_TYPE="update"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

@test "scope entrypoint: delete includes --no-params" {
  mock_np
  export SERVICE_ACTION="delete-scope"
  export SERVICE_ACTION_TYPE="custom"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

@test "scope entrypoint: diagnose includes --no-params" {
  mock_np
  export SERVICE_ACTION="diagnose-scope"
  export SERVICE_ACTION_TYPE="custom"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

@test "scope entrypoint: restart-pods includes --no-params" {
  mock_np
  export SERVICE_ACTION="restart-pods"
  export SERVICE_ACTION_TYPE="custom"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

# =============================================================================
# Backward compatibility - old CLI without --no-params support
# =============================================================================

@test "scope entrypoint: omits --no-params when CLI does not support it" {
  export NP_HELP_SUPPORTS_NO_PARAMS="false"
  mock_np
  export SERVICE_ACTION="create-scope"
  export SERVICE_ACTION_TYPE="create"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

# =============================================================================
# Core flags always present
# =============================================================================

@test "scope entrypoint: --build-context and --include-secrets always present" {
  mock_np
  export SERVICE_ACTION="create-scope"
  export SERVICE_ACTION_TYPE="create"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--build-context"
  assert_contains "$output" "--include-secrets"
}
