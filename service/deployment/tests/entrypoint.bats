#!/usr/bin/env bats
# =============================================================================
# Unit tests for service/deployment/entrypoint - --no-params flag behavior
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-456"
  export SERVICE_PATH="/tmp/test-service-path"
  export OVERRIDES_PATH=""

  mkdir -p "$SERVICE_PATH/deployment/workflows"
  touch "$SERVICE_PATH/deployment/workflows/initial.yaml"
  touch "$SERVICE_PATH/deployment/workflows/blue_green.yaml"
  touch "$SERVICE_PATH/deployment/workflows/switch_traffic.yaml"
  touch "$SERVICE_PATH/deployment/workflows/rollback.yaml"
  touch "$SERVICE_PATH/deployment/workflows/finalize.yaml"
  touch "$SERVICE_PATH/deployment/workflows/delete.yaml"
  touch "$SERVICE_PATH/deployment/workflows/diagnose.yaml"
  touch "$SERVICE_PATH/deployment/workflows/kill_instances.yaml"

  export NP_EXECUTED_CMD=""
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
# Actions that SHOULD include --no-params (when CLI supports it)
# =============================================================================

@test "deployment entrypoint: switch-traffic includes --no-params when CLI supports it" {
  mock_np
  export SERVICE_ACTION="switch-traffic"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

@test "deployment entrypoint: kill-instances includes --no-params when CLI supports it" {
  mock_np
  export SERVICE_ACTION="kill-instances"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

@test "deployment entrypoint: diagnose-deployment includes --no-params when CLI supports it" {
  mock_np
  export SERVICE_ACTION="diagnose-deployment"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--no-params"
}

# =============================================================================
# Actions that SHOULD NOT include --no-params
# =============================================================================

@test "deployment entrypoint: start-initial does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="start-initial"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: start-blue-green does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="start-blue-green"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: rollback-deployment does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="rollback-deployment"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: finalize-blue-green does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="finalize-blue-green"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: delete-deployment does NOT include --no-params" {
  mock_np
  export SERVICE_ACTION="delete-deployment"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

# =============================================================================
# Backward compatibility - old CLI without --no-params support
# =============================================================================

@test "deployment entrypoint: switch-traffic omits --no-params when CLI does not support it" {
  export NP_HELP_SUPPORTS_NO_PARAMS="false"
  mock_np
  export SERVICE_ACTION="switch-traffic"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

@test "deployment entrypoint: kill-instances omits --no-params when CLI does not support it" {
  export NP_HELP_SUPPORTS_NO_PARAMS="false"
  mock_np
  export SERVICE_ACTION="kill-instances"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-params"* ]]
}

# =============================================================================
# Edge cases
# =============================================================================

@test "deployment entrypoint: unknown action fails" {
  mock_np
  export SERVICE_ACTION="unknown-action"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Unknown action"
}

@test "deployment entrypoint: --build-context and --include-secrets always present" {
  mock_np
  export SERVICE_ACTION="switch-traffic"

  run bash "$BATS_TEST_DIRNAME/../entrypoint"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--build-context"
  assert_contains "$output" "--include-secrets"
}
