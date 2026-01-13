#!/bin/bash
# =============================================================================
# Test runner for all integration tests across all modules
#
# Usage:
#   ./testing/run_integration_tests.sh                    # Run all tests
#   ./testing/run_integration_tests.sh frontend           # Run tests for frontend module only
#   ./testing/run_integration_tests.sh --no-localstack    # Skip LocalStack management
#   ./testing/run_integration_tests.sh frontend --no-localstack
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
MANAGE_LOCALSTACK=true
MODULE=""

for arg in "$@"; do
  case $arg in
    --no-localstack)
      MANAGE_LOCALSTACK=false
      ;;
    *)
      MODULE="$arg"
      ;;
  esac
done

# Check if docker is installed
if ! command -v docker &> /dev/null; then
  echo -e "${RED}docker is not installed${NC}"
  echo ""
  echo "Install with:"
  echo "  brew install docker       # macOS"
  echo "  apt install docker.io     # Ubuntu/Debian"
  echo "  apk add docker            # Alpine"
  echo "  choco install docker      # Windows"
  exit 1
fi

# Check if docker compose is available
if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
  echo -e "${RED}docker compose is not installed${NC}"
  echo ""
  echo "Install with:"
  echo "  Docker Desktop includes docker compose"
  echo "  Or install separately: https://docs.docker.com/compose/install/"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}jq is not installed${NC}"
  echo ""
  echo "Install with:"
  echo "  brew install jq           # macOS"
  echo "  apt install jq            # Ubuntu/Debian"
  echo "  apk add jq                # Alpine"
  echo "  choco install jq          # Windows"
  exit 1
fi

# Check if aws cli is installed
if ! command -v aws &> /dev/null; then
  echo -e "${RED}aws-cli is not installed${NC}"
  echo ""
  echo "Install with:"
  echo "  brew install awscli       # macOS"
  echo "  apt install awscli        # Ubuntu/Debian"
  echo "  apk add aws-cli           # Alpine"
  echo "  choco install awscli      # Windows"
  exit 1
fi

# Check if shunit2 is installed
if ! command -v shunit2 &> /dev/null && \
   [ ! -f "/usr/local/bin/shunit2" ] && \
   [ ! -f "/usr/share/shunit2/shunit2" ] && \
   [ ! -f "/opt/homebrew/bin/shunit2" ]; then
  echo -e "${RED}shunit2 is not installed${NC}"
  echo ""
  echo "Install with:"
  echo "  brew install shunit2      # macOS"
  echo "  apt install shunit2       # Ubuntu/Debian"
  echo "  apk add shunit2           # Alpine"
  exit 1
fi

# Find all integration test directories
find_test_dirs() {
  find . -type d -name "integration" -path "*/tests/*" -not -path "*/node_modules/*" 2>/dev/null | sort
}

# Get module name from test path
get_module_name() {
  local path="$1"
  echo "$path" | sed 's|^\./||' | cut -d'/' -f1
}

# Find docker-compose.yml for a test directory (search up the tree)
find_docker_compose() {
  local dir="$1"
  local current="$dir"

  while [ "$current" != "$PROJECT_ROOT" ] && [ "$current" != "/" ]; do
    if [ -f "$current/docker-compose.yml" ]; then
      echo "$current/docker-compose.yml"
      return 0
    fi
    current="$(dirname "$current")"
  done

  return 1
}

# Start LocalStack
start_localstack() {
  local compose_file="$1"

  if [ -z "$compose_file" ]; then
    echo -e "${YELLOW}No docker-compose.yml found, skipping LocalStack${NC}"
    return 0
  fi

  echo -e "${CYAN}Starting LocalStack...${NC}"
  docker compose -f "$compose_file" up -d

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
  local compose_file="$1"

  if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
    echo -e "${CYAN}Stopping LocalStack...${NC}"
    docker compose -f "$compose_file" down -v 2>/dev/null || true
  fi
}

# Run a single test file
run_test_file() {
  local test_file="$1"
  local test_name=$(basename "$test_file" .sh)

  echo ""
  echo -e "${CYAN}Running: $test_name${NC}"
  echo "----------------------------------------"

  if bash "$test_file"; then
    echo -e "${GREEN}PASSED: $test_name${NC}"
    return 0
  else
    echo -e "${RED}FAILED: $test_name${NC}"
    return 1
  fi
}

# Run tests in a specific directory
run_tests_in_dir() {
  local test_dir="$1"
  local module_name=$(get_module_name "$test_dir")
  local passed=0
  local failed=0

  # Find test files
  local test_files=$(find "$test_dir" -maxdepth 1 -name "*_test.sh" 2>/dev/null | sort)

  if [ -z "$test_files" ]; then
    return 0
  fi

  echo -e "${CYAN}[$module_name]${NC} Running integration tests in $test_dir"
  echo ""

  for test_file in $test_files; do
    if [ -f "$test_file" ]; then
      if run_test_file "$test_file"; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1))
      fi
    fi
  done

  echo ""
  echo "  Passed: $passed, Failed: $failed"
  echo ""

  # Return failure if any test failed
  [ $failed -eq 0 ]
}

echo ""
echo "========================================"
echo "  Integration Tests"
echo "========================================"
echo ""

# Find docker-compose file for LocalStack
COMPOSE_FILE=""
if [ -n "$MODULE" ]; then
  # Look for docker-compose in the specified module
  for dir in $(find "$MODULE" -type d -name "integration" -path "*/tests/*" 2>/dev/null | head -1); do
    COMPOSE_FILE=$(find_docker_compose "$dir") || true
    break
  done
else
  # Look for docker-compose in first integration dir found
  for dir in $(find_test_dirs | head -1); do
    COMPOSE_FILE=$(find_docker_compose "$dir") || true
    break
  done
fi

# Manage LocalStack if requested
if [ "$MANAGE_LOCALSTACK" = true ] && [ -n "$COMPOSE_FILE" ]; then
  trap "stop_localstack '$COMPOSE_FILE'" EXIT
  start_localstack "$COMPOSE_FILE"
fi

# Track overall results
TOTAL_FAILED=0

if [ -n "$MODULE" ]; then
  # Run tests for specific module or directory
  if [ -d "$MODULE" ]; then
    # Find all integration test directories under the module
    module_test_dirs=$(find "$MODULE" -type d -name "integration" -path "*/tests/*" 2>/dev/null | sort)
    if [ -z "$module_test_dirs" ]; then
      echo -e "${RED}No integration test directories found in: $MODULE${NC}"
      exit 1
    fi
    for test_dir in $module_test_dirs; do
      if ! run_tests_in_dir "$test_dir"; then
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
      fi
    done
  else
    echo -e "${RED}Directory not found: $MODULE${NC}"
    echo ""
    echo "Available modules with integration tests:"
    for dir in $(find_test_dirs); do
      echo "  - $(get_module_name "$dir")"
    done | sort -u
    exit 1
  fi
else
  # Run all tests
  test_dirs=$(find_test_dirs)

  if [ -z "$test_dirs" ]; then
    echo -e "${YELLOW}No integration test directories found${NC}"
    exit 0
  fi

  for test_dir in $test_dirs; do
    if ! run_tests_in_dir "$test_dir"; then
      TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
  done
fi

if [ $TOTAL_FAILED -gt 0 ]; then
  echo -e "${RED}Some integration tests failed${NC}"
  exit 1
else
  echo -e "${GREEN}All integration tests passed!${NC}"
fi
