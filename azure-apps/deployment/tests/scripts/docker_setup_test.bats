#!/usr/bin/env bats
# =============================================================================
# Unit tests for docker_setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/scripts/docker_setup_test.bats
#
# Or run all tests:
#   bats tests/scripts/*.bats
# =============================================================================

# Setup - runs before each test
setup() {
  # Get the directory of the test file
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  SCRIPT_PATH="$PROJECT_DIR/scripts/docker_setup"

  # Load CONTEXT from test resources
  export CONTEXT=$(cat "$PROJECT_DIR/tests/resources/context.json")
}

# Teardown - runs after each test
teardown() {
  unset CONTEXT
  unset DOCKER_REGISTRY_URL
  unset DOCKER_REGISTRY_USERNAME
  unset DOCKER_REGISTRY_PASSWORD
}

# =============================================================================
# Helper functions
# =============================================================================
run_docker_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Validation success messages
# =============================================================================
@test "Should display validation header message" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Validating Docker registry configuration..."
}

@test "Should display success message when all values are set" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✨ Docker registry configured successfully"
}

@test "Should display variable values when validation passes" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✅ DOCKER_REGISTRY_URL=https://testregistry.azurecr.io"
  assert_contains "$output" "✅ DOCKER_REGISTRY_USERNAME=test-registry-user"
  assert_contains "$output" "✅ DOCKER_REGISTRY_PASSWORD=****"
  assert_contains "$output" "✅ DOCKER_IMAGE=tools/automation:v1.0.0"
}

# =============================================================================
# Test: Context value extraction
# =============================================================================
@test "Should extract DOCKER_REGISTRY_URL from context with https prefix" {
  run_docker_setup

  assert_equal "$DOCKER_REGISTRY_URL" "https://testregistry.azurecr.io"
}

@test "Should extract DOCKER_REGISTRY_USERNAME from context" {
  run_docker_setup

  assert_equal "$DOCKER_REGISTRY_USERNAME" "test-registry-user"
}

@test "Should extract DOCKER_REGISTRY_PASSWORD from context" {
  run_docker_setup

  assert_equal "$DOCKER_REGISTRY_PASSWORD" "test-registry-password"
}

# =============================================================================
# Test: Context-derived variables - Validation errors
# =============================================================================
@test "Should fail when server is missing from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["assets-repository"].setup.server)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ DOCKER_REGISTRY_SERVER could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Verify that you have a Docker server asset provider provider linked to this scope."
  assert_contains "$output" "• server"
}

@test "Should fail when username is missing from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["assets-repository"].setup.username)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ DOCKER_REGISTRY_USERNAME could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• username"
}

@test "Should fail when password is missing from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["assets-repository"].setup.password)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ DOCKER_REGISTRY_PASSWORD could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• password"
}

@test "Should fail when assets-repository provider is missing from context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["assets-repository"])')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ DOCKER_REGISTRY_SERVER could not be resolved from providers"
  assert_contains "$output" "❌ DOCKER_REGISTRY_USERNAME could not be resolved from providers"
  assert_contains "$output" "❌ DOCKER_REGISTRY_PASSWORD could not be resolved from providers"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Verify that you have a Docker server asset provider provider linked to this scope."
}

@test "Should list all missing fields when multiple are absent" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["assets-repository"].setup.server, .providers["assets-repository"].setup.username)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "• server"
  assert_contains "$output" "• username"
}

# =============================================================================
# Test: Environment variable exports
# =============================================================================
@test "Should export DOCKER_REGISTRY_URL" {
  run_docker_setup

  assert_equal "$DOCKER_REGISTRY_URL" "https://testregistry.azurecr.io"
}

@test "Should export DOCKER_REGISTRY_USERNAME" {
  run_docker_setup

  assert_equal "$DOCKER_REGISTRY_USERNAME" "test-registry-user"
}

@test "Should export DOCKER_REGISTRY_PASSWORD" {
  run_docker_setup

  assert_equal "$DOCKER_REGISTRY_PASSWORD" "test-registry-password"
}

# =============================================================================
# Test: Docker image extraction
# =============================================================================
@test "Should extract DOCKER_IMAGE from asset URL with registry server stripped" {
  run_docker_setup

  assert_equal "$DOCKER_IMAGE" "tools/automation:v1.0.0"
}

@test "Should export DOCKER_IMAGE" {
  run_docker_setup

  assert_equal "$DOCKER_IMAGE" "tools/automation:v1.0.0"
}
