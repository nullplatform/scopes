#!/bin/bash
# =============================================================================
# Test runner for all BATS tests across all modules
#
# Usage:
#   ./run_tests.sh                    # Run all tests
#   ./run_tests.sh frontend           # Run tests for frontend module only
#   ./run_tests.sh frontend/deployment/tests/aws  # Run specific test directory
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

# Check if bats is installed
if ! command -v bats &> /dev/null; then
  echo -e "${RED}bats-core is not installed${NC}"
  echo ""
  echo "Install with:"
  echo "  brew install bats-core    # macOS"
  echo "  apt install bats          # Ubuntu/Debian"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}jq is not installed${NC}"
  echo ""
  echo "Install with:"
  echo "  brew install jq    # macOS"
  echo "  apt install jq     # Ubuntu/Debian"
  exit 1
fi

# Find all test directories
find_test_dirs() {
  find . -type d -name "tests" -path "*/deployment/*" 2>/dev/null | sort
}

# Get module name from test path
get_module_name() {
  local path="$1"
  echo "$path" | sed 's|^\./||' | cut -d'/' -f1
}

# Run tests for a specific directory
run_tests_in_dir() {
  local test_dir="$1"
  local module_name=$(get_module_name "$test_dir")

  # Find all .bats files recursively
  local bats_files=$(find "$test_dir" -name "*.bats" 2>/dev/null)

  if [ -z "$bats_files" ]; then
    return 0
  fi

  echo -e "${CYAN}[$module_name]${NC} Running BATS tests in $test_dir"
  echo ""

  (
    cd "$test_dir"
    # Use script to force TTY for colored output
    script -q /dev/null bats --formatter pretty $(find . -name "*.bats" | sort)
  )

  echo ""
}

echo ""
echo "========================================"
echo "  BATS Tests"
echo "========================================"
echo ""

if [ -n "$1" ]; then
  # Run tests for specific module or directory
  if [ -d "$1" ]; then
    # Direct directory path
    run_tests_in_dir "$1"
  elif [ -d "$1/deployment/tests" ]; then
    # Module name (e.g., "frontend")
    run_tests_in_dir "$1/deployment/tests"
  else
    echo -e "${RED}Test directory not found: $1${NC}"
    echo ""
    echo "Available modules with tests:"
    for dir in $(find_test_dirs); do
      echo "  - $(get_module_name "$dir")"
    done
    exit 1
  fi
else
  # Run all tests
  test_dirs=$(find_test_dirs)

  if [ -z "$test_dirs" ]; then
    echo -e "${YELLOW}No test directories found${NC}"
    exit 0
  fi

  for test_dir in $test_dirs; do
    run_tests_in_dir "$test_dir"
  done
fi

echo -e "${GREEN}All BATS tests passed!${NC}"
