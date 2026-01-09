#!/bin/bash
# =============================================================================
# Test runner for all tests (BATS + OpenTofu)
#
# Usage:
#   ./run_all_tests.sh              # Run all tests
#   ./run_all_tests.sh frontend     # Run tests for frontend module only
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

MODULE="${1:-}"

echo ""
echo "========================================"
echo "  Running All Tests"
echo "========================================"
echo ""

# Track failures
BATS_FAILED=0
TOFU_FAILED=0

# Run BATS tests
echo -e "${CYAN}[BATS]${NC} Running bash tests..."
echo ""
if ./run_tests.sh $MODULE; then
  echo -e "${GREEN}[BATS] All bash tests passed${NC}"
else
  BATS_FAILED=1
  echo -e "${RED}[BATS] Some bash tests failed${NC}"
fi

echo ""
echo "----------------------------------------"
echo ""

# Run OpenTofu tests
echo -e "${CYAN}[TOFU]${NC} Running OpenTofu tests..."
echo ""
if ./run_tofu_tests.sh $MODULE; then
  echo -e "${GREEN}[TOFU] All OpenTofu tests passed${NC}"
else
  TOFU_FAILED=1
  echo -e "${RED}[TOFU] Some OpenTofu tests failed${NC}"
fi

echo ""
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""

if [ $BATS_FAILED -eq 0 ] && [ $TOFU_FAILED -eq 0 ]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  [ $BATS_FAILED -eq 1 ] && echo -e "${RED}BATS tests: FAILED${NC}"
  [ $BATS_FAILED -eq 0 ] && echo -e "${GREEN}BATS tests: PASSED${NC}"
  [ $TOFU_FAILED -eq 1 ] && echo -e "${RED}OpenTofu tests: FAILED${NC}"
  [ $TOFU_FAILED -eq 0 ] && echo -e "${GREEN}OpenTofu tests: PASSED${NC}"
  exit 1
fi
