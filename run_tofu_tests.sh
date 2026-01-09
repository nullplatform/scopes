#!/bin/bash
# =============================================================================
# Test runner for all OpenTofu/Terraform tests across all modules
#
# Usage:
#   ./run_tofu_tests.sh                           # Run all tofu tests
#   ./run_tofu_tests.sh frontend                  # Run tests for frontend module
#   ./run_tofu_tests.sh frontend/provider/aws     # Run specific module tests
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

# Check if tofu is installed
if ! command -v tofu &> /dev/null; then
  echo -e "${RED}OpenTofu is not installed${NC}"
  echo ""
  echo "Install with:"
  echo "  brew install opentofu    # macOS"
  echo "  See https://opentofu.org/docs/intro/install/"
  exit 1
fi

# Find all directories with .tftest.hcl files
find_tofu_test_dirs() {
  find . -name "*.tftest.hcl" -path "*/deployment/*" 2>/dev/null | xargs -I{} dirname {} | sort -u
}

# Get module name from path
get_module_name() {
  local path="$1"
  echo "$path" | sed 's|^\./||' | cut -d'/' -f1
}

# Get relative module path (e.g., provider/aws/modules)
get_relative_path() {
  local path="$1"
  echo "$path" | sed 's|^\./[^/]*/deployment/||'
}

# Run tests for a specific directory
run_tofu_tests_in_dir() {
  local test_dir="$1"
  local module_name=$(get_module_name "$test_dir")
  local relative_path=$(get_relative_path "$test_dir")

  echo -e "${CYAN}[$module_name]${NC} ${relative_path}"

  (
    cd "$test_dir"

    # Initialize if needed (without backend)
    if [ ! -d ".terraform" ]; then
      tofu init -backend=false -input=false >/dev/null 2>&1 || true
    fi

    # Run tests
    tofu test
  )

  echo ""
}

echo ""
echo "========================================"
echo "  OpenTofu Tests"
echo "========================================"
echo ""

if [ -n "$1" ]; then
  # Run tests for specific module or directory
  if [ -d "$1" ] && ls "$1"/*.tftest.hcl &>/dev/null; then
    # Direct directory with test files
    run_tofu_tests_in_dir "$1"
  elif [ -d "$1/deployment" ]; then
    # Module name (e.g., "frontend")
    module_dirs=$(find "$1/deployment" -name "*.tftest.hcl" 2>/dev/null | xargs -I{} dirname {} | sort -u)
    if [ -z "$module_dirs" ]; then
      echo -e "${YELLOW}No tofu test files found in $1${NC}"
      exit 0
    fi
    for dir in $module_dirs; do
      run_tofu_tests_in_dir "$dir"
    done
  elif [ -d "$1/modules" ] && ls "$1/modules"/*.tftest.hcl &>/dev/null; then
    # Path like "frontend/provider/aws" -> check frontend/deployment/provider/aws/modules
    run_tofu_tests_in_dir "$1/modules"
  else
    # Try to find it under deployment
    for base in */deployment; do
      if [ -d "$base/$1/modules" ] && ls "$base/$1/modules"/*.tftest.hcl &>/dev/null 2>&1; then
        run_tofu_tests_in_dir "$base/$1/modules"
        exit 0
      fi
    done
    echo -e "${RED}No tofu test files found for: $1${NC}"
    echo ""
    echo "Available modules with tofu tests:"
    for dir in $(find_tofu_test_dirs); do
      local module=$(get_module_name "$dir")
      local rel=$(get_relative_path "$dir")
      echo "  - $module: $rel"
    done
    exit 1
  fi
else
  # Run all tests
  test_dirs=$(find_tofu_test_dirs)

  if [ -z "$test_dirs" ]; then
    echo -e "${YELLOW}No tofu test files found${NC}"
    exit 0
  fi

  for test_dir in $test_dirs; do
    run_tofu_tests_in_dir "$test_dir"
  done
fi

echo -e "${GREEN}All OpenTofu tests passed!${NC}"
