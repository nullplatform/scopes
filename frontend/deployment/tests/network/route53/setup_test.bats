#!/usr/bin/env bats
# =============================================================================
# Unit tests for network/route53/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/network/route53/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/network/route53/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"
  AWS_MOCKS_DIR="$RESOURCES_DIR/aws_mocks"
  NP_MOCKS_DIR="$RESOURCES_DIR/np_mocks"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Add mock aws and np to PATH (must be first)
  export PATH="$AWS_MOCKS_DIR:$NP_MOCKS_DIR:$PATH"

  # Load context with hosted_public_zone_id
  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools", "id": "7"},
    "providers": {
      "cloud-providers": {
        "networking": {
          "hosted_public_zone_id": "Z1234567890ABC"
        }
      }
    }
  }'

  # Initialize TOFU_VARIABLES with existing keys to verify script merges (not replaces)
  export TOFU_VARIABLES='{
    "application_slug": "automation",
    "scope_slug": "development-tools",
    "scope_id": "7"
  }'

  export MODULES_TO_USE=""

  # Set default np scope patch mock (success)
  export NP_MOCK_SCOPE_PATCH_RESPONSE="$NP_MOCKS_DIR/scope/patch/success.json"
  export NP_MOCK_SCOPE_PATCH_EXIT_CODE="0"
}

# =============================================================================
# Helper functions
# =============================================================================
run_route53_setup() {
  source "$SCRIPT_PATH"
}

set_aws_mock() {
  local mock_file="$1"
  local exit_code="${2:-0}"
  export AWS_MOCK_RESPONSE="$AWS_MOCKS_DIR/route53/$mock_file"
  export AWS_MOCK_EXIT_CODE="$exit_code"
}

set_np_scope_patch_mock() {
  local mock_file="$1"
  local exit_code="${2:-0}"
  export NP_MOCK_SCOPE_PATCH_RESPONSE="$NP_MOCKS_DIR/scope/patch/$mock_file"
  export NP_MOCK_SCOPE_PATCH_EXIT_CODE="$exit_code"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "TOFU_VARIABLES matches expected structure on success" {
  set_aws_mock "success.json"

  run_route53_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "network_hosted_zone_id": "Z1234567890ABC",
  "network_domain": "example.com",
  "network_subdomain": "automation-development-tools"
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "adds module to MODULES_TO_USE when empty" {
  set_aws_mock "success.json"

  run_route53_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/network/route53/modules"
}

@test "appends module to existing MODULES_TO_USE" {
  set_aws_mock "success.json"
  export MODULES_TO_USE="existing/module"

  run_route53_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/network/route53/modules"
}

# =============================================================================
# Test: Missing hosted_zone_id in context
# =============================================================================
@test "fails when hosted_public_zone_id is missing from context" {
  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools"},
    "providers": {
      "cloud-providers": {
        "networking": {}
      }
    }
  }'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "hosted_public_zone_id is not set in context"
}

# =============================================================================
# Test: NoSuchHostedZone error
# =============================================================================
@test "fails when hosted zone does not exist" {
  set_aws_mock "no_such_zone.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Failed to fetch Route 53 hosted zone information"
}

@test "shows helpful message for NoSuchHostedZone error" {
  set_aws_mock "no_such_zone.json" 1

  run source "$SCRIPT_PATH"

  assert_contains "$output" "Hosted zone"
  assert_contains "$output" "does not exist"
}

# =============================================================================
# Test: AccessDenied error
# =============================================================================
@test "fails when access is denied" {
  set_aws_mock "access_denied.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Failed to fetch Route 53 hosted zone information"
}

@test "shows permission denied message for AccessDenied error" {
  set_aws_mock "access_denied.json" 1

  run source "$SCRIPT_PATH"

  assert_contains "$output" "Permission denied"
}

# =============================================================================
# Test: InvalidInput error
# =============================================================================
@test "fails when hosted zone ID is invalid" {
  set_aws_mock "invalid_input.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Failed to fetch Route 53 hosted zone information"
}

@test "shows invalid format message for InvalidInput error" {
  set_aws_mock "invalid_input.json" 1

  run source "$SCRIPT_PATH"

  assert_contains "$output" "Invalid hosted zone ID format"
}

# =============================================================================
# Test: Credentials error
# =============================================================================
@test "fails when AWS credentials are missing" {
  set_aws_mock "credentials_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Failed to fetch Route 53 hosted zone information"
}

@test "shows credentials message for credentials error" {
  set_aws_mock "credentials_error.json" 1

  run source "$SCRIPT_PATH"

  assert_contains "$output" "AWS credentials issue"
}

# =============================================================================
# Test: Empty domain in response
# =============================================================================
@test "fails when domain cannot be extracted from response" {
  set_aws_mock "empty_domain.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Failed to extract domain name from hosted zone response"
}

# =============================================================================
# Test: Scope patch success
# =============================================================================
@test "shows setting scope domain message" {
  set_aws_mock "success.json"
  set_np_scope_patch_mock "success.json"

  run source "$SCRIPT_PATH"

  assert_contains "$output" "Setting scope domain"
}

@test "shows scope domain set successfully message" {
  set_aws_mock "success.json"
  set_np_scope_patch_mock "success.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "Scope domain set successfully"
}

# =============================================================================
# Test: Scope patch auth error
# =============================================================================
@test "fails when scope patch returns auth error" {
  set_aws_mock "success.json"
  set_np_scope_patch_mock "auth_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "Failed to update scope domain"
}

@test "shows permission denied message for scope patch auth error" {
  set_aws_mock "success.json"
  set_np_scope_patch_mock "auth_error.json" 1

  run source "$SCRIPT_PATH"

  assert_contains "$output" "Permission denied"
}
