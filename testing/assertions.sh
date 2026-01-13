# =============================================================================
# Shared assertion functions for BATS tests
#
# Usage: Add this line at the top of your .bats file's setup() function:
#   source "$PROJECT_ROOT/testing/assertions.sh"
# =============================================================================

# =============================================================================
# Assertion functions
# =============================================================================

assert_equal() {
  local actual="$1"
  local expected="$2"
  if [ "$actual" != "$expected" ]; then
    echo "Expected: '$expected'"
    echo "Actual:   '$actual'"
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Expected string to contain: '$needle'"
    echo "Actual: '$haystack'"
    return 1
  fi
}

assert_not_empty() {
  local value="$1"
  local name="${2:-value}"
  if [ -z "$value" ]; then
    echo "Expected $name to be non-empty, but it was empty"
    return 1
  fi
}

assert_empty() {
  local value="$1"
  local name="${2:-value}"
  if [ -n "$value" ]; then
    echo "Expected $name to be empty"
    echo "Actual: '$value'"
    return 1
  fi
}

assert_directory_exists() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "Expected directory to exist: '$dir'"
    return 1
  fi
}

assert_file_exists() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Expected file to exist: '$file'"
    return 1
  fi
}

assert_json_equal() {
  local actual="$1"
  local expected="$2"
  local name="${3:-JSON}"

  local actual_sorted=$(echo "$actual" | jq -S .)
  local expected_sorted=$(echo "$expected" | jq -S .)

  if [ "$actual_sorted" != "$expected_sorted" ]; then
    echo "$name does not match expected structure"
    echo ""
    echo "Expected:"
    echo "$expected_sorted"
    echo ""
    echo "Actual:"
    echo "$actual_sorted"
    echo ""
    echo "Diff:"
    diff <(echo "$expected_sorted") <(echo "$actual_sorted") || true
    return 1
  fi
}
