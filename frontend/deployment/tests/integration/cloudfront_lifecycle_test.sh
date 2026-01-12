#!/bin/bash
# =============================================================================
# Integration test: CloudFront distribution lifecycle
#
# Tests the full lifecycle of creating and destroying CloudFront infrastructure
# using shunit2 test framework.
#
# Run: ./run_integration_tests.sh cloudfront_lifecycle_test.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set integration test directory before sourcing utilities
export INTEGRATION_TEST_DIR="$SCRIPT_DIR"

# Source test utilities from shared location
. "$SCRIPT_DIR/../integration_test_utils.sh"

# =============================================================================
# Test Setup/Teardown
# =============================================================================

oneTimeSetUp() {
  # Start LocalStack once for all tests in this file
  localstack_start
}

oneTimeTearDown() {
  # Stop LocalStack after all tests complete
  localstack_stop
}

setUp() {
  # Reset LocalStack state before each test
  localstack_reset
}

tearDown() {
  # Cleanup after each test if needed
  :
}

# =============================================================================
# Tests
# =============================================================================

test_create_and_destroy_cloudfront_distribution() {
  # Load test configuration
  load_test_config "$SCRIPT_DIR/configs/example_create_and_destroy.json"

  # Execute all steps defined in the config
  execute_all_steps

  # If we get here without failures, the test passed
  assertTrue "All steps completed successfully" true
}

# =============================================================================
# Load shunit2
# =============================================================================

# Find shunit2 - check common locations
if [ -f "/usr/local/bin/shunit2" ]; then
  . /usr/local/bin/shunit2
elif [ -f "/usr/share/shunit2/shunit2" ]; then
  . /usr/share/shunit2/shunit2
elif [ -f "/opt/homebrew/bin/shunit2" ]; then
  . /opt/homebrew/bin/shunit2
elif command -v shunit2 &> /dev/null; then
  . "$(command -v shunit2)"
else
  echo "Error: shunit2 not found"
  echo ""
  echo "Install with:"
  echo "  brew install shunit2    # macOS"
  echo "  apt install shunit2     # Ubuntu/Debian"
  exit 1
fi
