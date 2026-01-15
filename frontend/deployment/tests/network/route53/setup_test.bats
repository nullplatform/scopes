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
  export NP_MOCK_RESPONSE="$NP_MOCKS_DIR/scope/patch/success.json"
  export NP_MOCK_EXIT_CODE="0"
}

# =============================================================================
# Helper functions
# =============================================================================
run_route53_setup() {
  source "$SCRIPT_PATH"
}

#set_np_scope_patch_mock() {
#  local mock_file="$1"
#  local exit_code="${2:-0}"
#  export NP_MOCK_RESPONSE="$mock_file"
#  export NP_MOCK_EXIT_CODE="$exit_code"
#}

# =============================================================================
# Test: Required environment variables
# =============================================================================
@test "Should fail when hosted_public_zone_id is not present in context" {
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
  assert_contains "$output" "   ❌ hosted_public_zone_id is not set in context"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    1. Ensure there is an AWS cloud-provider configured at the correct NRN hierarchy level"
  assert_contains "$output" "    2. Set the 'hosted_public_zone_id' field with the Route 53 hosted zone ID"
}

# =============================================================================
# Test: NoSuchHostedZone error
# =============================================================================
@test "Should fail if hosted zone does not exist" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/no_such_zone.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to fetch Route 53 hosted zone information"
  assert_contains "$output" "  🔎 Error: Hosted zone 'Z1234567890ABC' does not exist"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The hosted zone ID is incorrect or has a typo"
  assert_contains "$output" "    • The hosted zone was deleted"
  assert_contains "$output" "    • The hosted zone ID format is wrong (should be like 'Z1234567890ABC' or '/hostedzone/Z1234567890ABC')"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    1. Verify the hosted zone exists: aws route53 list-hosted-zones"
  assert_contains "$output" "    2. Update 'hosted_public_zone_id' in the AWS cloud-provider configuration"
}

# =============================================================================
# Test: AccessDenied error
# =============================================================================
@test "Should fail if lacking permissions to read hosted zones" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/access_denied.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  🔒 Error: Permission denied when accessing Route 53"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The AWS credentials don't have Route 53 read permissions"
  assert_contains "$output" "    • The IAM role/user is missing the 'route53:GetHostedZone' permission"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    1. Check the AWS credentials are configured correctly"
  assert_contains "$output" "    2. Ensure the IAM policy includes:"
}

# =============================================================================
# Test: InvalidInput error
# =============================================================================
@test "Should fail if hosted zone id is not valid" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/invalid_input.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  ⚠️  Error: Invalid hosted zone ID format"
  assert_contains "$output" "  The hosted zone ID 'Z1234567890ABC' is not valid."

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Use the format 'Z1234567890ABC' or '/hostedzone/Z1234567890ABC'"
  assert_contains "$output" "    • Find valid zone IDs with: aws route53 list-hosted-zones"
}

# =============================================================================
# Test: Credentials error
# =============================================================================
@test "Should fail if AWS credentials are missing" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/credentials_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  🔑 Error: AWS credentials issue"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The nullplatform agent is not configured with AWS credentials"
  assert_contains "$output" "    • The IAM role associated with the service account does not exist"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    1. Configure a service account in the nullplatform agent Helm installation"
  assert_contains "$output" "    2. Verify the IAM role associated with the service account exists and has the required permissions"
  assert_contains "$output" "  🔑 Error: AWS credentials issue"
}

# =============================================================================
# Test: Unknown Route53 error
# =============================================================================
@test "Should handle unknown error getting the route53 hosted zone" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/unknown_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  📋 Error details:"
  assert_contains "$output" "Unknown error getting route53 hosted zone."

}

# =============================================================================
# Test: Empty domain in response
# =============================================================================
@test "Should handle missing hosted zone name from response" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/empty_domain.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to extract domain name from hosted zone response"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The hosted zone does not have a valid domain name configured"
  assert_contains "$output" "   ❌ Failed to extract domain name from hosted zone response"

  assert_contains "$output" "   ❌ Failed to extract domain name from hosted zone response"
  assert_contains "$output" "    1. Verify the hosted zone has a valid domain: aws route53 get-hosted-zone --id Z1234567890ABC"
}

# =============================================================================
# Test: Scope patch error
# =============================================================================
@test "Should handle auth error updating scope domain" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/success.json"
  set_np_mock "$NP_MOCKS_DIR/scope/patch/auth_error.json" 1

  run source "$SCRIPT_PATH"

#  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to update scope domain"
  assert_contains "$output" "  🔒 Error: Permission denied"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The nullplatform API Key doesn't have 'Developer' permissions"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    1. Ensure the API Key has 'Developer' permissions at the correct NRN hierarchy level"
}

@test "Should handle unknown error updating scope domain" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/success.json"
  set_np_mock "$NP_MOCKS_DIR/scope/patch/unknown_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to update scope domain"
  assert_contains "$output" "  📋 Error details:"
  assert_contains "$output" "Unknown error updating scope"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add network variables to TOFU_VARIABLES" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/success.json"

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
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/success.json"

  run_route53_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/network/route53/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  set_aws_mock "$AWS_MOCKS_DIR/route53/success.json"
  export MODULES_TO_USE="existing/module"

  run_route53_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/network/route53/modules"
}