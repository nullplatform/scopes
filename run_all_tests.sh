#!/bin/bash
# =============================================================================
# Test runner for all tests (BATS + OpenTofu + Integration)
#
# Usage:
#   ./run_all_tests.sh                      # Run all tests
#   ./run_all_tests.sh frontend             # Run tests for frontend module only
#   ./run_all_tests.sh --skip-integration   # Skip integration tests
#   ./run_all_tests.sh --only-integration   # Run only integration tests
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
MODULE=""
SKIP_INTEGRATION=false
ONLY_INTEGRATION=false

for arg in "$@"; do
  case $arg in
    --skip-integration)
      SKIP_INTEGRATION=true
      ;;
    --only-integration)
      ONLY_INTEGRATION=true
      ;;
    *)
      MODULE="$arg"
      ;;
  esac
done

echo ""
echo "========================================"
echo "  Running All Tests"
echo "========================================"
echo ""

# Track failures
BATS_FAILED=0
TOFU_FAILED=0
INTEGRATION_FAILED=0

# Run unit tests unless only-integration is specified
if [ "$ONLY_INTEGRATION" = false ]; then
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
fi

# Run integration tests unless skip-integration is specified
if [ "$SKIP_INTEGRATION" = false ]; then
  echo ""
  echo "----------------------------------------"
  echo ""

  echo -e "${CYAN}[INTEGRATION]${NC} Running integration tests..."
  echo ""
  if ./run_integration_tests.sh $MODULE; then
    echo -e "${GREEN}[INTEGRATION] All integration tests passed${NC}"
  else
    INTEGRATION_FAILED=1
    echo -e "${RED}[INTEGRATION] Some integration tests failed${NC}"
  fi
fi

# Summary
echo ""
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""

ALL_PASSED=true

if [ "$ONLY_INTEGRATION" = false ]; then
  if [ $BATS_FAILED -eq 0 ]; then
    echo -e "${GREEN}BATS tests: PASSED${NC}"
  else
    echo -e "${RED}BATS tests: FAILED${NC}"
    ALL_PASSED=false
  fi

  if [ $TOFU_FAILED -eq 0 ]; then
    echo -e "${GREEN}OpenTofu tests: PASSED${NC}"
  else
    echo -e "${RED}OpenTofu tests: FAILED${NC}"
    ALL_PASSED=false
  fi
fi

if [ "$SKIP_INTEGRATION" = false ]; then
  if [ $INTEGRATION_FAILED -eq 0 ]; then
    echo -e "${GREEN}Integration tests: PASSED${NC}"
  else
    echo -e "${RED}Integration tests: FAILED${NC}"
    ALL_PASSED=false
  fi
fi

echo ""

if [ "$ALL_PASSED" = true ]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed${NC}"
  exit 1
fi
