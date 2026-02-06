#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/print_failed_deployment_hints - error hints display
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export CONTEXT='{
    "scope": {
      "name": "my-app",
      "dimensions": "production",
      "capabilities": {
        "health_check": {
          "path": "/health"
        },
        "ram_memory": 512
      }
    }
  }'
}

teardown() {
  unset CONTEXT
}

# =============================================================================
# Hints Display Test
# =============================================================================
@test "print_failed_deployment_hints: displays complete troubleshooting hints" {
  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  # Main header
  assert_contains "$output" "⚠️  Application Startup Issue Detected"
  # Possible causes
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Your application was unable to start"
  # How to fix section
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "port 8080"
  assert_contains "$output" "/health"
  assert_contains "$output" "Application Logs"
  assert_contains "$output" "512Mi"
  assert_contains "$output" "Environment Variables"
  assert_contains "$output" "my-app"
  assert_contains "$output" "production"
}
