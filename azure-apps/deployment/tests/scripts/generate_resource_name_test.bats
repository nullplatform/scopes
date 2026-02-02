#!/usr/bin/env bats
# =============================================================================
# Unit tests for generate_resource_name script
#
# Requirements:
#   - bats-core: brew install bats-core
#
# Run tests:
#   bats tests/scripts/generate_resource_name_test.bats
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

  SCRIPT_PATH="$PROJECT_DIR/scripts/generate_resource_name"
}

# =============================================================================
# Test: Basic functionality
# =============================================================================
@test "Should generate name with all segments when within max length" {
  run "$SCRIPT_PATH" 60 "namespace" "application" "scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "namespace-application-scope-12345"
}

@test "Should generate name with two segments plus ID" {
  run "$SCRIPT_PATH" 60 "namespace" "scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "namespace-scope-12345"
}

@test "Should generate name with single segment plus ID" {
  run "$SCRIPT_PATH" 60 "namespace" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "namespace-12345"
}

@test "Should return just ID when only ID is provided" {
  run "$SCRIPT_PATH" 60 "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "12345"
}

# =============================================================================
# Test: Truncation behavior
# =============================================================================
@test "Should remove leftmost segment when name exceeds max length" {
  # namespace-application-scope-12345 = 33 chars
  # With max_length=30, should become: application-scope-12345 = 23 chars
  run "$SCRIPT_PATH" 30 "namespace" "application" "scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "application-scope-12345"
}

@test "Should remove multiple segments from left when necessary" {
  # namespace-application-scope-12345 = 33 chars
  # With max_length=20, should become: scope-12345 = 11 chars
  run "$SCRIPT_PATH" 20 "namespace" "application" "scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "scope-12345"
}

@test "Should truncate last segment as last resort when no more hyphens" {
  # namespace-application-scope-12345 = 33 chars
  # With max_length=10, suffix is -12345 (6 chars), max_prefix_length=4
  # After removing namespace and application, "scope" remains but has no hyphens
  # So it truncates "scope" to "scop" (4 chars) -> "scop-12345"
  run "$SCRIPT_PATH" 10 "namespace" "application" "scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "scop-12345"
}

@test "Should return just ID when prefix becomes empty" {
  # When max_prefix_length is 0 or negative, only ID should remain
  run "$SCRIPT_PATH" 6 "namespace" "application" "scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "12345"
}

@test "Should handle exact max length boundary" {
  # namespace-application-scope-12345 = 33 chars
  run "$SCRIPT_PATH" 33 "namespace" "application" "scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "namespace-application-scope-12345"
}

@test "Should truncate when one char over max length" {
  # namespace-application-scope-12345 = 33 chars
  # With max_length=32, needs truncation -> application-scope-12345 = 23 chars
  run "$SCRIPT_PATH" 32 "namespace" "application" "scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "application-scope-12345"
}

# =============================================================================
# Test: Azure App Service name constraints (60 char max)
# =============================================================================
@test "Should handle Azure App Service max length (60 chars)" {
  run "$SCRIPT_PATH" 60 "production-namespace" "my-application" "development-scope" "999999"

  assert_equal "$status" "0"
  # production-namespace-my-application-development-scope-999999 = 60 chars (exactly at limit)
  local result_length=${#output}
  assert_less_than "$result_length" "61" "name length"
}

@test "Should truncate long Azure names correctly" {
  # very-long-namespace-name-my-application-name-development-scope-name-999999 > 60 chars
  run "$SCRIPT_PATH" 60 "very-long-namespace-name" "my-application-name" "development-scope-name" "999999"

  assert_equal "$status" "0"
  local result_length=${#output}
  assert_less_than "$result_length" "61" "name length"
  # Should always end with the ID
  assert_contains "$output" "-999999"
}

# =============================================================================
# Test: Edge cases
# =============================================================================
@test "Should handle segments with hyphens" {
  run "$SCRIPT_PATH" 60 "my-namespace" "my-app" "my-scope" "12345"

  assert_equal "$status" "0"
  assert_equal "$output" "my-namespace-my-app-my-scope-12345"
}

@test "Should handle numeric segments" {
  run "$SCRIPT_PATH" 60 "123" "456" "789"

  assert_equal "$status" "0"
  assert_equal "$output" "123-456-789"
}

@test "Should handle single character segments" {
  run "$SCRIPT_PATH" 60 "a" "b" "c" "1"

  assert_equal "$status" "0"
  assert_equal "$output" "a-b-c-1"
}

@test "Should keep prefix when it fits within max length" {
  # app-1 = 5 chars, which fits within max_length=5
  run "$SCRIPT_PATH" 5 "namespace" "app" "1"

  assert_equal "$status" "0"
  assert_equal "$output" "app-1"
}

@test "Should return just ID when max_length equals ID length plus hyphen" {
  # When max_length only allows for the ID and hyphen, prefix is dropped
  run "$SCRIPT_PATH" 2 "namespace" "app" "1"

  assert_equal "$status" "0"
  assert_equal "$output" "1"
}

# =============================================================================
# Test: Error handling
# =============================================================================
@test "Should fail with usage message when no arguments provided" {
  run "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Usage:"
}

@test "Should fail with usage message when only max_length provided" {
  run "$SCRIPT_PATH" 60

  assert_equal "$status" "1"
  assert_contains "$output" "Usage:"
}

# =============================================================================
# Test: Real-world scenarios
# =============================================================================
@test "Should generate valid name for typical nullplatform deployment" {
  run "$SCRIPT_PATH" 60 "tools" "automation" "development-tools" "7"

  assert_equal "$status" "0"
  assert_equal "$output" "tools-automation-development-tools-7"
}

@test "Should handle long org names in nullplatform" {
  run "$SCRIPT_PATH" 60 "enterprise-production" "customer-portal" "staging-environment" "12345678"

  assert_equal "$status" "0"
  # Should fit within 60 chars
  local result_length=${#output}
  assert_less_than "$result_length" "61" "name length"
  # Should end with scope ID
  assert_contains "$output" "-12345678"
}
