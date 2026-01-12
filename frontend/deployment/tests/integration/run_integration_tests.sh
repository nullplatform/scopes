#!/bin/bash
# =============================================================================
# Integration test runner for shunit2 tests
#
# Usage:
#   ./run_integration_tests.sh                    # Run all integration tests
#   ./run_integration_tests.sh test_file.sh       # Run specific test file
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
MANAGE_LOCALSTACK=true
SPECIFIC_TEST=""

for arg in "$@"; do
  case $arg in
    --no-localstack)
      MANAGE_LOCALSTACK=false
      ;;
    *.sh)
      SPECIFIC_TEST="$arg"
      ;;
  esac
done

# Check dependencies
check_dependencies() {
  local missing=()

  if ! command -v docker &> /dev/null; then
    missing+=("docker")
  fi

  if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    missing+=("docker-compose")
  fi

  if ! command -v jq &> /dev/null; then
    missing+=("jq")
  fi

  if ! command -v aws &> /dev/null; then
    missing+=("aws-cli")
  fi

  # Check for shunit2
  if ! command -v shunit2 &> /dev/null && \
     [ ! -f "/usr/local/bin/shunit2" ] && \
     [ ! -f "/usr/share/shunit2/shunit2" ] && \
     [ ! -f "/opt/homebrew/bin/shunit2" ]; then
    missing+=("shunit2")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${RED}Missing dependencies:${NC}"
    for dep in "${missing[@]}"; do
      echo "  - $dep"
    done
    echo ""
    echo "Install with:"
    echo "  brew install docker jq awscli shunit2    # macOS"
    exit 1
  fi
}

# Start LocalStack
start_localstack() {
  echo -e "${CYAN}Starting LocalStack...${NC}"
  docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

  echo "Waiting for LocalStack to be ready..."
  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if curl -s "http://localhost:4566/_localstack/health" | jq -e '.services.s3 == "running"' > /dev/null 2>&1; then
      echo -e "${GREEN}LocalStack is ready${NC}"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
    echo -n "."
  done

  echo ""
  echo -e "${RED}LocalStack failed to start${NC}"
  return 1
}

# Stop LocalStack
stop_localstack() {
  echo -e "${CYAN}Stopping LocalStack...${NC}"
  docker compose -f "$SCRIPT_DIR/docker-compose.yml" down -v
}

# Run a single test file
run_test_file() {
  local test_file="$1"
  local test_name=$(basename "$test_file" .sh)

  echo ""
  echo -e "${CYAN}Running: $test_name${NC}"
  echo "========================================"

  if bash "$test_file"; then
    echo -e "${GREEN}PASSED: $test_name${NC}"
    return 0
  else
    echo -e "${RED}FAILED: $test_name${NC}"
    return 1
  fi
}

# Main
echo ""
echo "========================================"
echo "  Integration Tests (shunit2)"
echo "========================================"
echo ""

check_dependencies

# Manage LocalStack if requested
if [ "$MANAGE_LOCALSTACK" = true ]; then
  # Ensure LocalStack is stopped on exit
  trap stop_localstack EXIT
  start_localstack
fi

# Find and run tests
FAILED=0
PASSED=0

if [ -n "$SPECIFIC_TEST" ]; then
  # Run specific test
  if [ -f "$SPECIFIC_TEST" ]; then
    if run_test_file "$SPECIFIC_TEST"; then
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  else
    echo -e "${RED}Test file not found: $SPECIFIC_TEST${NC}"
    exit 1
  fi
else
  # Run all test files
  for test_file in "$SCRIPT_DIR"/*_test.sh; do
    if [ -f "$test_file" ]; then
      if run_test_file "$test_file"; then
        PASSED=$((PASSED + 1))
      else
        FAILED=$((FAILED + 1))
      fi
    fi
  done
fi

# Summary
echo ""
echo "========================================"
echo "  Summary"
echo "========================================"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -gt 0 ]; then
  echo ""
  echo -e "${RED}Some integration tests failed${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}All integration tests passed!${NC}"
  exit 0
fi
