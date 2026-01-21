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

# Setup once for all tests in this file
setup_file() {
  export TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  export PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  export SCRIPT_PATH="$PROJECT_DIR/scripts/do_tofu"

  # Create temporary directories once for all tests
  export TEST_OUTPUT_DIR=$(mktemp -d)
  export MOCK_BIN_DIR=$(mktemp -d)
  export MOCK_TOFU_SOURCE=$(mktemp -d)

  # Create mock tofu source files
  echo 'resource "azurerm_app_service" "main" {}' > "$MOCK_TOFU_SOURCE/main.tf"
  echo 'variable "app_name" {}' > "$MOCK_TOFU_SOURCE/variables.tf"
  mkdir -p "$MOCK_TOFU_SOURCE/scripts"
  echo '#!/bin/bash' > "$MOCK_TOFU_SOURCE/scripts/helper.sh"

  # Setup mock tofu command
  cat > "$MOCK_BIN_DIR/tofu" << 'EOF'
#!/bin/bash
echo "tofu $*" >> "$TOFU_MOCK_LOG"
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/tofu"
}

# Cleanup once after all tests
teardown_file() {
  rm -rf "$TEST_OUTPUT_DIR" "$MOCK_BIN_DIR" "$MOCK_TOFU_SOURCE"
}

# Setup before each test - just reset state
setup() {
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Reset environment for each test
  export TF_WORKING_DIR="$TEST_OUTPUT_DIR/terraform"
  export OUTPUT_DIR="$TEST_OUTPUT_DIR"
  export TOFU_VARIABLES='{"app_name": "test-app", "docker_image": "test:latest"}'
  export TOFU_INIT_VARIABLES="-backend-config=storage_account_name=tfstate"
  export TOFU_ACTION="apply"
  export TOFU_MOCK_LOG="$TEST_OUTPUT_DIR/tofu_calls.log"
  export DEPLOYMENT_ID="123"
  export APP_NAME="test-app"
  export SCOPE_ID="7"
  export SERVICE_PATH="$PROJECT_DIR"
  export TOFU_PATH="$MOCK_TOFU_SOURCE"
  export PATH="$MOCK_BIN_DIR:$PATH"

  # Clean up from previous test
  rm -rf "$TF_WORKING_DIR" "$TOFU_MOCK_LOG" "$OUTPUT_DIR/tofu.tfvars.json"
  mkdir -p "$TF_WORKING_DIR"

  # Restore default mock (some tests override it)
  cat > "$MOCK_BIN_DIR/tofu" << 'EOF'
#!/bin/bash
echo "tofu $*" >> "$TOFU_MOCK_LOG"
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/tofu"
}

# =============================================================================
# Test: Output messages
# =============================================================================
@test "Should display deployment information at start" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Running tofu apply for deployment: 123"
  assert_contains "$output" "📋 App Service: test-app"
}

@test "Should display initialization message" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Initializing tofu..."
}

@test "Should display generated tfvars" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Generated tfvars:"
}

@test "Should display action message" {
  export TOFU_ACTION="apply"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Running tofu apply..."
}

@test "Should display completion message for apply" {
  export TOFU_ACTION="apply"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✅ Tofu apply completed successfully"
}

@test "Should display completion message for destroy" {
  export TOFU_ACTION="destroy"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✅ Tofu destroy completed successfully"
}

# =============================================================================
# Test: Tofu file copying
# =============================================================================
@test "Should copy .tf files from tofu source" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TF_WORKING_DIR/main.tf"
  assert_file_exists "$TF_WORKING_DIR/variables.tf"
}

@test "Should copy scripts directory from tofu source" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_directory_exists "$TF_WORKING_DIR/scripts"
}

@test "Should use SERVICE_PATH/modules as default source" {
  unset TOFU_PATH
  mkdir -p "$SERVICE_PATH/modules"
  echo 'resource "test" {}' > "$SERVICE_PATH/modules/test.tf"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  rm -rf "$SERVICE_PATH/modules"
}

# =============================================================================
# Test: tfvars file creation
# =============================================================================
@test "Should write TOFU_VARIABLES to tfvars.json file" {
  export TOFU_VARIABLES='{"environment": "production", "replicas": 3}'

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$OUTPUT_DIR/tofu.tfvars.json"

  local content
  content=$(cat "$OUTPUT_DIR/tofu.tfvars.json")
  assert_equal "$content" '{"environment": "production", "replicas": 3}'
}

@test "Should create valid JSON in tfvars file" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  run jq '.' "$OUTPUT_DIR/tofu.tfvars.json"
  assert_equal "$status" "0"
}

# =============================================================================
# Test: Tofu init command
# =============================================================================
@test "Should call tofu init with -chdir" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TOFU_MOCK_LOG"

  local init_call
  init_call=$(grep "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$init_call" "tofu -chdir=$TF_WORKING_DIR init"
}

@test "Should call tofu init with -input=false" {
  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local init_call
  init_call=$(grep "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$init_call" "-input=false"
}

@test "Should call tofu init with TOFU_INIT_VARIABLES" {
  export TOFU_INIT_VARIABLES="-backend-config=storage_account_name=mystorageaccount -backend-config=container_name=tfstate"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local init_call
  init_call=$(grep "init" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$init_call" "-backend-config=storage_account_name=mystorageaccount"
  assert_contains "$init_call" "-backend-config=container_name=tfstate"
}

# =============================================================================
# Test: Tofu action command
# =============================================================================
@test "Should call tofu apply with -chdir" {
  export TOFU_ACTION="apply"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call
  action_call=$(grep "apply" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "tofu -chdir=$TF_WORKING_DIR apply"
}

@test "Should call tofu with -auto-approve" {
  export TOFU_ACTION="apply"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call
  action_call=$(grep "apply" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "-auto-approve"
}

@test "Should call tofu with -var-file" {
  export TOFU_ACTION="apply"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call
  action_call=$(grep "apply" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "-var-file=$OUTPUT_DIR/tofu.tfvars.json"
}

@test "Should call tofu destroy when TOFU_ACTION is destroy" {
  export TOFU_ACTION="destroy"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"

  local action_call
  action_call=$(grep "destroy" "$TOFU_MOCK_LOG" | head -1)
  assert_contains "$action_call" "tofu -chdir=$TF_WORKING_DIR destroy"
}

# =============================================================================
# Test: Default TOFU_ACTION
# =============================================================================
@test "Should use apply as default TOFU_ACTION" {
  unset TOFU_ACTION

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Running tofu apply for deployment:"
}

# =============================================================================
# Test: Command execution order
# =============================================================================
@test "Should call tofu init before action" {
  export TOFU_ACTION="apply"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_command_order "$TOFU_MOCK_LOG" \
    "tofu -chdir=$TF_WORKING_DIR init" \
    "tofu -chdir=$TF_WORKING_DIR apply"
}

# =============================================================================
# Test: Error handling
# =============================================================================
@test "Should fail if tofu init fails" {
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
  cat > "$MOCK_BIN_DIR/tofu" << 'EOF'
#!/bin/bash
echo "tofu $*" >> "$TOFU_MOCK_LOG"
if [[ "$*" == *"apply"* ]]; then
  echo "Error: Apply failed" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/tofu"

  run bash "$SCRIPT_PATH"

  assert_equal "$status" "1"
}
