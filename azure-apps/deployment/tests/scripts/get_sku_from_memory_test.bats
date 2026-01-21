#!/usr/bin/env bats
# =============================================================================
# Unit tests for get_sku_from_memory script
#
# Requirements:
#   - bats-core: brew install bats-core
#
# Run tests:
#   bats tests/scripts/get_sku_from_memory_test.bats
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

  SCRIPT_PATH="$PROJECT_DIR/scripts/get_sku_from_memory"
}

# =============================================================================
# Test: Valid memory values - SKU mapping
# =============================================================================
@test "Should return S1 for 2 GB memory" {
  run "$SCRIPT_PATH" 2

  assert_equal "$status" "0"
  assert_equal "$output" "S1"
}

@test "Should return S2 for 4 GB memory" {
  run "$SCRIPT_PATH" 4

  assert_equal "$status" "0"
  assert_equal "$output" "S2"
}

@test "Should return P1v3 for 8 GB memory" {
  run "$SCRIPT_PATH" 8

  assert_equal "$status" "0"
  assert_equal "$output" "P1v3"
}

@test "Should return P2v3 for 16 GB memory" {
  run "$SCRIPT_PATH" 16

  assert_equal "$status" "0"
  assert_equal "$output" "P2v3"
}

@test "Should return P3v3 for 32 GB memory" {
  run "$SCRIPT_PATH" 32

  assert_equal "$status" "0"
  assert_equal "$output" "P3v3"
}

# =============================================================================
# Test: Error handling - Invalid memory values
# =============================================================================
@test "Should fail with error message for invalid memory value 1" {
  run "$SCRIPT_PATH" 1

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Invalid memory value: 1"
  assert_contains "$output" "💡 Valid memory values are: 2, 4, 8, 16, 32 (in GB)"
  assert_contains "$output" "🔧 How to fix:"
}

@test "Should fail with error message for invalid memory value 3" {
  run "$SCRIPT_PATH" 3

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Invalid memory value: 3"
}

@test "Should fail with error message for invalid memory value 64" {
  run "$SCRIPT_PATH" 64

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Invalid memory value: 64"
}

@test "Should fail with error message for non-numeric value" {
  run "$SCRIPT_PATH" "large"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Invalid memory value: large"
}

@test "Should fail with error message for empty string" {
  run "$SCRIPT_PATH" ""

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Invalid memory value:"
}

@test "Should fail with error message for negative value" {
  run "$SCRIPT_PATH" "-8"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Invalid memory value: -8"
}

@test "Should fail with error message for decimal value" {
  run "$SCRIPT_PATH" "2.5"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Invalid memory value: 2.5"
}

# =============================================================================
# Test: Error handling - Missing argument
# =============================================================================
@test "Should fail with usage message when no argument provided" {
  run "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Missing required argument: memory"
  assert_contains "$output" "Usage:"
  assert_contains "$output" "Valid memory values: 2, 4, 8, 16, 32"
}

# =============================================================================
# Test: Error message includes fix instructions
# =============================================================================
@test "Should include all valid options in fix instructions" {
  run "$SCRIPT_PATH" 100

  assert_equal "$status" "1"
  assert_contains "$output" "• 2 GB  - Standard tier (S1)"
  assert_contains "$output" "• 4 GB  - Standard tier (S2)"
  assert_contains "$output" "• 8 GB  - Premium tier (P1v3)"
  assert_contains "$output" "• 16 GB - Premium tier (P2v3)"
  assert_contains "$output" "• 32 GB - Premium tier (P3v3)"
}
