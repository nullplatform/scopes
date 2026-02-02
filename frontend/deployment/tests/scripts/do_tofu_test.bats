#!/usr/bin/env bats
# =============================================================================
# Unit tests for do_tofu script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/scripts/do_tofu_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/scripts/do_tofu"

  source "$PROJECT_ROOT/testing/assertions.sh"

  # Create temporary directory for testing
  TEST_OUTPUT_DIR=$(mktemp -d)
  MOCK_BIN_DIR=$(mktemp -d)

  # Setup mock tofu command
  cat > "$MOCK_BIN_DIR/tofu" << 'EOF'
#!/bin/bash
# Mock tofu command - logs calls to a file for verification
echo "tofu $*" >> "$TOFU_MOCK_LOG"
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/tofu"

  # Export environment variables
  export TOFU_MODULE_DIR="$TEST_OUTPUT_DIR"
  export TOFU_VARIABLES='{"key": "value", "number": 42}'
  export TOFU_INIT_VARIABLES="-backend-config=bucket=test-bucket -backend-config=region=us-east-1"
  export TOFU_ACTION="apply"
  export TOFU_MOCK_LOG="$TEST_OUTPUT_DIR/tofu_calls.log"

  # Add mock bin to PATH
  export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
  # Clean up temp directories
  if [ -d "$TEST_OUTPUT_DIR" ]; then
    rm -rf "$TEST_OUTPUT_DIR"
  fi
  if [ -d "$MOCK_BIN_DIR" ]; then
    rm -rf "$MOCK_BIN_DIR"
  fi
}

# =============================================================================
# Test: tfvars file creation
# =============================================================================
@test "Should write TOFU_VARIABLES to .tfvars.json file" {
  export TOFU_VARIABLES='{"environment": "production", "replicas": 3}'

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TOFU_MODULE_DIR/.tfvars.json"

  local content=$(cat "$TOFU_MODULE_DIR/.tfvars.json")
  assert_equal "$content" '{"environment": "production", "replicas": 3}'

  # Verify it's valid JSON by parsing with jq
  run jq '.' "$TOFU_MODULE_DIR/.tfvars.json"
  assert_equal "$status" "0"
}

# =============================================================================
# Test: tofu init command
# =============================================================================
@test "Should call tofu init with correct chdir" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TOFU_MOCK_LOG"

  local init_call=$(grep "tofu -chdir=" "$TOFU_MOCK_LOG" | grep "init" | head -1)
  assert_contains "$init_call" "-chdir=$TOFU_MODULE_DIR"
}

@test "Should call tofu init with -input=false" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local init_call=$(grep "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$init_call" "-input=false"
}

@test "Should call tofu init with TOFU_INIT_VARIABLES" {
  export TOFU_INIT_VARIABLES="-backend-config=bucket=my-bucket -backend-config=key=state.tfstate"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local init_call=$(grep "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$init_call" "-backend-config=bucket=my-bucket"
  assert_contains "$init_call" "-backend-config=key=state.tfstate"
}

@test "Should call tofu init with empty TOFU_INIT_VARIABLES" {
  export TOFU_INIT_VARIABLES=""

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local init_call=$(grep "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$init_call" "init -input=false"
}

# =============================================================================
# Test: tofu action command
# =============================================================================
@test "Should call tofu with TOFU_ACTION=apply" {
  export TOFU_ACTION="apply"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call=$(grep -v "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "apply"
}

@test "Should call tofu with TOFU_ACTION=destroy" {
  export TOFU_ACTION="destroy"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call=$(grep -v "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "destroy"
}

@test "Should call tofu with TOFU_ACTION=plan" {
  export TOFU_ACTION="plan"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call=$(grep -v "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "plan"
}

@test "Should call tofu action with -auto-approve" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call=$(grep -v "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "-auto-approve"
}

@test "Should call tofu action with correct var-file path" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call=$(grep -v "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "-var-file=$TOFU_MODULE_DIR/.tfvars.json"
}

@test "Should call tofu action with correct chdir" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call=$(grep -v "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "-chdir=$TOFU_MODULE_DIR"
}

# =============================================================================
# Test: Command execution order
# =============================================================================
@test "Should call tofu init before tofu action" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_command_order "$TOFU_MOCK_LOG" \
    "tofu -chdir=$TOFU_MODULE_DIR init" \
    "tofu -chdir=$TOFU_MODULE_DIR apply"
}

# =============================================================================
# Test: Error handling
# =============================================================================
@test "Should fail if tofu init fails" {
  # Create a failing mock
  cat > "$MOCK_BIN_DIR/tofu" << 'EOF'
#!/bin/bash
if [[ "$*" == *"init"* ]]; then
  echo "Error: Failed to initialize" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/tofu"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "1"
}

@test "Should fail if tofu action fails" {
  # Create a mock that fails on action
  cat > "$MOCK_BIN_DIR/tofu" << 'EOF'
#!/bin/bash
if [[ "$*" == *"apply"* ]] || [[ "$*" == *"destroy"* ]] || [[ "$*" == *"plan"* ]]; then
  if [[ "$*" != *"init"* ]]; then
    echo "Error: Action failed" >&2
    exit 1
  fi
fi
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/tofu"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "1"
}