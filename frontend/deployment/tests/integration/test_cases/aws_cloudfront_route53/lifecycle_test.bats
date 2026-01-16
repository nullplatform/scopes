#!/usr/bin/env bats
# =============================================================================
# Integration test: CloudFront + Route53 Lifecycle
#
# Tests the full lifecycle of a static frontend deployment:
#   1. Create infrastructure (CloudFront distribution + Route53 record)
#   2. Verify all resources are configured correctly
#   3. Destroy infrastructure
#   4. Verify all resources are removed
# =============================================================================

# =============================================================================
# Test Constants
# =============================================================================
# Expected values derived from context.json and terraform variables

# CloudFront variables (distribution/cloudfront/modules/variables.tf)
TEST_DISTRIBUTION_BUCKET="assets-bucket"                                    # distribution_bucket_name
TEST_DISTRIBUTION_S3_PREFIX="/tools/automation/v1.0.0"                      # distribution_s3_prefix
TEST_DISTRIBUTION_APP_NAME="automation-development-tools-7"                 # distribution_app_name
TEST_DISTRIBUTION_COMMENT="Distribution for automation-development-tools-7" # derived from app_name

# Route53 variables (network/route53/modules/variables.tf)
TEST_NETWORK_DOMAIN="frontend.publicdomain.com"                             # network_domain
TEST_NETWORK_SUBDOMAIN="automation-development-tools"                       # network_subdomain
TEST_NETWORK_FULL_DOMAIN="automation-development-tools.frontend.publicdomain.com"  # computed

# =============================================================================
# Test Setup
# =============================================================================

setup_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  source "${PROJECT_ROOT}/testing/assertions.sh"
  integration_setup --cloud-provider aws

  clear_mocks

  # Create AWS prerequisites
  echo "Creating test prerequisites..."
  aws_local s3api create-bucket --bucket assets-bucket >/dev/null 2>&1 || true
  aws_local s3api create-bucket --bucket tofu-state-bucket >/dev/null 2>&1 || true
  aws_local dynamodb create-table \
    --table-name tofu-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null 2>&1 || true
  aws_local route53 create-hosted-zone \
    --name "$TEST_NETWORK_DOMAIN" \
    --caller-reference "test-$(date +%s)" >/dev/null 2>&1 || true

  # Create ACM certificate for the test domain
  aws_local acm request-certificate \
    --domain-name "*.$TEST_NETWORK_DOMAIN" \
    --validation-method DNS >/dev/null 2>&1 || true

  # Get hosted zone ID for context override
  HOSTED_ZONE_ID=$(aws_local route53 list-hosted-zones --query 'HostedZones[0].Id' --output text | sed 's|/hostedzone/||')
  export HOSTED_ZONE_ID
}

teardown_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  clear_mocks
  integration_teardown
}

setup() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  source "${PROJECT_ROOT}/testing/assertions.sh"
  source "${BATS_TEST_DIRNAME}/cloudfront_assertions.bash"
  source "${BATS_TEST_DIRNAME}/route53_assertions.bash"

  clear_mocks
  load_context "frontend/deployment/tests/resources/context.json"
  override_context "providers.cloud-providers.networking.hosted_public_zone_id" "$HOSTED_ZONE_ID"

  # Export environment variables
  export NETWORK_LAYER="route53"
  export DISTRIBUTION_LAYER="cloudfront"
  export TOFU_PROVIDER="aws"
  export TOFU_PROVIDER_BUCKET="tofu-state-bucket"
  export TOFU_LOCK_TABLE="tofu-locks"
  export AWS_REGION="us-east-1"
  export SERVICE_PATH="$INTEGRATION_MODULE_ROOT/frontend"
  export CUSTOM_TOFU_MODULES="$INTEGRATION_MODULE_ROOT/frontend/deployment/tests/integration/localstack"

  # Setup API mocks for np CLI calls
  local mocks_dir="frontend/deployment/tests/integration/mocks/"
  mock_request "GET" "/category" "$mocks_dir/asset_repository/category.json"
  mock_request "GET" "/provider_specification" "$mocks_dir/asset_repository/list_provider_spec.json"
  mock_request "GET" "/provider" "$mocks_dir/asset_repository/list_provider.json"
  mock_request "GET" "/provider/s3-asset-repository-id" "$mocks_dir/asset_repository/get_provider.json"
  mock_request "PATCH" "/scope/7" "$mocks_dir/scope/patch.json"
}

# =============================================================================
# Test: Create Infrastructure
# =============================================================================

@test "create infrastructure deploys CloudFront and Route53 resources" {
  run_workflow "frontend/deployment/workflows/initial.yaml"

  assert_cloudfront_configured \
    "$TEST_DISTRIBUTION_COMMENT" \
    "$TEST_NETWORK_FULL_DOMAIN" \
    "$TEST_DISTRIBUTION_BUCKET" \
    "$TEST_DISTRIBUTION_S3_PREFIX"

  assert_route53_configured \
    "$TEST_NETWORK_FULL_DOMAIN" \
    "A" \
    "$HOSTED_ZONE_ID"
}

# =============================================================================
# Test: Destroy Infrastructure
# =============================================================================

@test "destroy infrastructure removes CloudFront and Route53 resources" {
  # Disable CloudFront before deletion (required by AWS)
  if [[ -f "$BATS_TEST_DIRNAME/../../scripts/disable_cloudfront.sh" ]]; then
    "$BATS_TEST_DIRNAME/../../scripts/disable_cloudfront.sh" "$TEST_DISTRIBUTION_COMMENT"
  fi

  run_workflow "frontend/deployment/workflows/delete.yaml"

  assert_cloudfront_not_configured "$TEST_DISTRIBUTION_COMMENT"
  assert_route53_not_configured "$TEST_NETWORK_FULL_DOMAIN" "A" "$HOSTED_ZONE_ID"
}
