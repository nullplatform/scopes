#!/bin/bash
# =============================================================================
# Integration test runner for all modules
#
# Usage:
#   ./run_integration_tests.sh                    # Run all integration tests
#   ./run_integration_tests.sh frontend           # Run tests for frontend module
#   ./run_integration_tests.sh --no-localstack    # Skip LocalStack management
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
EXTRA_ARGS=""
MODULE=""

for arg in "$@"; do
  case $arg in
    --no-localstack)
      EXTRA_ARGS="$EXTRA_ARGS --no-localstack"
      ;;
    *)
      MODULE="$arg"
      ;;
  esac
done

# Find all integration test directories
find_integration_dirs() {
  find . -type d -name "integration" -path "*/deployment/tests/*" 2>/dev/null | sort
}

# Get module name from test path
get_module_name() {
  local path="$1"
  echo "$path" | sed 's|^\./||' | cut -d'/' -f1
}

# Run integration tests for a specific directory
run_integration_in_dir() {
  local test_dir="$1"
  local module_name=$(get_module_name "$test_dir")

  if [ ! -f "$test_dir/run_integration_tests.sh" ]; then
    return 0
  fi

  echo -e "${CYAN}[$module_name]${NC} Running integration tests in $test_dir"
  echo ""

  (
    cd "$test_dir"
    ./run_integration_tests.sh $EXTRA_ARGS
  )

  echo ""
}

echo ""
echo "========================================"
echo "  Integration Tests"
echo "========================================"
echo ""

if [ -n "$MODULE" ]; then
  # Run tests for specific module
  if [ -d "$MODULE/deployment/tests/integration" ]; then
    run_integration_in_dir "$MODULE/deployment/tests/integration"
  else
    echo -e "${RED}Integration test directory not found for: $MODULE${NC}"
    echo ""
    echo "Available modules with integration tests:"
    for dir in $(find_integration_dirs); do
      echo "  - $(get_module_name "$dir")"
    done
    exit 1
  fi
else
  # Run all integration tests
  integration_dirs=$(find_integration_dirs)

  if [ -z "$integration_dirs" ]; then
    echo -e "${YELLOW}No integration test directories found${NC}"
    exit 0
  fi

  for test_dir in $integration_dirs; do
    run_integration_in_dir "$test_dir"
  done
fi

echo -e "${GREEN}All integration tests passed!${NC}"
