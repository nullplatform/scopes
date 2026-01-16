#!/usr/bin/env bats
# =============================================================================
# Unit tests for compose_modules script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/scripts/compose_modules_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/scripts/compose_modules"

  source "$PROJECT_ROOT/testing/assertions.sh"

  # Create temporary directories for testing
  TEST_OUTPUT_DIR=$(mktemp -d)
  TEST_MODULES_DIR=$(mktemp -d)

  export TOFU_MODULE_DIR="$TEST_OUTPUT_DIR"
}

teardown() {
  # Clean up temp directories
  if [ -d "$TEST_OUTPUT_DIR" ]; then
    rm -rf "$TEST_OUTPUT_DIR"
  fi
  if [ -d "$TEST_MODULES_DIR" ]; then
    rm -rf "$TEST_MODULES_DIR"
  fi
}

# =============================================================================
# Helper functions
# =============================================================================
create_test_module() {
  local module_path="$1"
  local module_dir="$TEST_MODULES_DIR/$module_path"
  mkdir -p "$module_dir"
  echo "$module_dir"
}

create_tf_file() {
  local module_dir="$1"
  local filename="$2"
  local content="${3:-# Test terraform file}"
  echo "$content" > "$module_dir/$filename"
}

create_setup_script() {
  local module_dir="$1"
  local content="${2:-echo 'Setup executed'}"
  echo "#!/bin/bash" > "$module_dir/setup"
  echo "$content" >> "$module_dir/setup"
  chmod +x "$module_dir/setup"
}

# =============================================================================
# Test: Required environment variables - Error messages
# =============================================================================
@test "Should fail when MODULES_TO_USE is not set" {
  unset MODULES_TO_USE

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "🔍 Validating module composition configuration..."
  assert_contains "$output" "   ❌ MODULES_TO_USE is not set"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Ensure MODULES_TO_USE is set before calling compose_modules"
  assert_contains "$output" "    • This is typically done by the setup scripts (provider, network, distribution)"
}

@test "Should fail when TOFU_MODULE_DIR is not set" {
  export MODULES_TO_USE="some/module"
  unset TOFU_MODULE_DIR

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "🔍 Validating module composition configuration..."
  assert_contains "$output" "   ❌ TOFU_MODULE_DIR is not set"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Ensure TOFU_MODULE_DIR is set before calling compose_modules"
  assert_contains "$output" "    • This is typically done by the build_context script"
}

@test "Should fail when module directory does not exist" {
  export MODULES_TO_USE="/nonexistent/module/path"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Module directory not found: /nonexistent/module/path"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Verify the module path is correct and the directory exists"
}

# =============================================================================
# Test: Validation success messages
# =============================================================================
@test "Should display validation header message" {
  local module_dir=$(create_test_module "test/module")
  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Validating module composition configuration..."
}

@test "Should display modules and target in validation output" {
  local module_dir=$(create_test_module "test/module")
  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "   ✅ modules=$module_dir"
  assert_contains "$output" "   ✅ target=$TOFU_MODULE_DIR"
}

# =============================================================================
# Test: Module processing messages
# =============================================================================
@test "Should display module path with package emoji when processing" {
  local module_dir=$(create_test_module "network/route53")
  create_tf_file "$module_dir" "main.tf"
  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "📦 $module_dir"
}

@test "Should display each copied file name" {
  local module_dir=$(create_test_module "network/route53")
  create_tf_file "$module_dir" "main.tf"
  create_tf_file "$module_dir" "variables.tf"
  create_tf_file "$module_dir" "outputs.tf"
  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "   main.tf"
  assert_contains "$output" "   variables.tf"
  assert_contains "$output" "   outputs.tf"
}

@test "Should display copy success message with file count and prefix" {
  local module_dir=$(create_test_module "network/route53")
  create_tf_file "$module_dir" "main.tf"
  create_tf_file "$module_dir" "variables.tf"
  create_tf_file "$module_dir" "outputs.tf"
  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "   ✅ Copied 3 file(s) with prefix: network_route53_"
}

@test "Should display setup script running message" {
  local module_dir=$(create_test_module "provider/aws")
  create_setup_script "$module_dir" "echo 'AWS provider configured'"

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "   📡 Running setup script..."
}

@test "Should display setup completed message" {
  local module_dir=$(create_test_module "provider/aws")
  create_setup_script "$module_dir" "echo 'AWS provider configured'"

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "   ✅ Setup completed"
}

@test "Should display final success message" {
  local module_dir=$(create_test_module "test/module")
  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✨ All modules composed successfully"
}

# =============================================================================
# Test: Setup script failure messages
# =============================================================================
@test "Should display setup failed message when setup script fails" {
  local module_dir=$(create_test_module "provider/aws")
  # Use 'return 1' instead of 'exit 1' since sourced scripts that call exit
  # will exit the entire parent script before the error message can be printed
  create_setup_script "$module_dir" "echo 'Error during setup'; return 1"

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   📡 Running setup script..."
  assert_contains "$output" "   ❌ Setup script failed for module: $module_dir"
}

# =============================================================================
# Test: Module copying functionality
# =============================================================================
@test "Should copy .tf files to TOFU_MODULE_DIR" {
  local module_dir=$(create_test_module "network/route53")
  create_tf_file "$module_dir" "main.tf" "resource \"aws_route53_record\" \"main\" {}"
  create_tf_file "$module_dir" "variables.tf" "variable \"domain\" {}"

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TOFU_MODULE_DIR/network_route53_main.tf"
  assert_file_exists "$TOFU_MODULE_DIR/network_route53_variables.tf"
}

@test "Should skip test_*.tf files when copying" {
  local module_dir=$(create_test_module "network/route53")
  create_tf_file "$module_dir" "main.tf"
  create_tf_file "$module_dir" "test_locals.tf"

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TOFU_MODULE_DIR/network_route53_main.tf"
  assert_file_not_exists "$TOFU_MODULE_DIR/network_route53_test_locals.tf"
}

@test "Should use correct prefix based on parent and leaf directory names" {
  local module_dir=$(create_test_module "provider/aws")
  create_tf_file "$module_dir" "provider.tf"

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TOFU_MODULE_DIR/provider_aws_provider.tf"
}

@test "Should handle modules with no .tf files" {
  local module_dir=$(create_test_module "custom/empty")
  # Don't create any .tf files

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✨ All modules composed successfully"
}

# =============================================================================
# Test: Multiple modules
# =============================================================================
@test "Should process multiple modules from comma-separated list" {
  local module1=$(create_test_module "provider/aws")
  local module2=$(create_test_module "network/route53")
  create_tf_file "$module1" "provider.tf"
  create_tf_file "$module2" "main.tf"

  export MODULES_TO_USE="$module1,$module2"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TOFU_MODULE_DIR/provider_aws_provider.tf"
  assert_file_exists "$TOFU_MODULE_DIR/network_route53_main.tf"
  # Verify both modules were logged
  assert_contains "$output" "📦 $module1"
  assert_contains "$output" "📦 $module2"
}

@test "Should handle whitespace in comma-separated module list" {
  local module1=$(create_test_module "provider/aws")
  local module2=$(create_test_module "network/route53")
  create_tf_file "$module1" "provider.tf"
  create_tf_file "$module2" "main.tf"

  export MODULES_TO_USE="$module1 , $module2"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_file_exists "$TOFU_MODULE_DIR/provider_aws_provider.tf"
  assert_file_exists "$TOFU_MODULE_DIR/network_route53_main.tf"
}

# =============================================================================
# Test: Setup scripts execution
# =============================================================================
@test "Should execute setup script and display its output" {
  local module_dir=$(create_test_module "provider/aws")
  create_setup_script "$module_dir" "echo 'Custom setup message from AWS provider'"

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Custom setup message from AWS provider"
}

@test "Should not fail if module has no setup script" {
  local module_dir=$(create_test_module "custom/nosetup")
  create_tf_file "$module_dir" "main.tf"
  # Don't create a setup script

  export MODULES_TO_USE="$module_dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✨ All modules composed successfully"
}

# =============================================================================
# Test: TOFU_MODULE_DIR creation
# =============================================================================
@test "Should create TOFU_MODULE_DIR if it does not exist" {
  local module_dir=$(create_test_module "test/module")
  export MODULES_TO_USE="$module_dir"
  export TOFU_MODULE_DIR="$TEST_OUTPUT_DIR/nested/deep/dir"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_directory_exists "$TOFU_MODULE_DIR"
}
