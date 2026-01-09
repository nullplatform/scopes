#!/bin/bash
# =============================================================================
# Test runner for all BATS tests
#
# Usage:
#   ./tests/run_tests.sh              # Run all tests
#   ./tests/run_tests.sh aws          # Run tests in aws/ directory
#   ./tests/run_tests.sh build_context # Run specific test file
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
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

# Run specific test or all tests
if [ -n "$1" ]; then
  # Check if it's a directory
  if [ -d "$1" ]; then
    echo "Running tests in $1/"
    bats "$1"/*.bats
  # Check if it's a file (with or without .bats extension)
  elif [ -f "${1}_test.bats" ]; then
    echo "Running ${1}_test.bats"
    bats "${1}_test.bats"
  elif [ -f "$1" ]; then
    echo "Running $1"
    bats "$1"
  else
    echo -e "${RED}Test not found: $1${NC}"
    exit 1
  fi
else
  echo "Running all tests..."
  echo ""
  bats ./*.bats ./**/*.bats
fi

echo ""
echo -e "${GREEN}All tests passed!${NC}"
