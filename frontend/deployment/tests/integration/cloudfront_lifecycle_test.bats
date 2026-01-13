#!/usr/bin/env bats
# =============================================================================
# Integration test: CloudFront Distribution Lifecycle
#
# Tests the full lifecycle: create infrastructure, verify it exists,
# then destroy it and verify cleanup.
# =============================================================================

setup_file() {
  # Load integration helpers
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"

  # Clear any existing mocks
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
    --name frontend.publicdomain.com \
    --caller-reference "test-$(date +%s)" >/dev/null 2>&1 || true

  # Get hosted zone ID for context override
  HOSTED_ZONE_ID=$(aws_local route53 list-hosted-zones --query 'HostedZones[0].Id' --output text | sed 's|/hostedzone/||')

  export HOSTED_ZONE_ID
}

teardown_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  clear_mocks
}

# Setup runs before each test
setup() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"

  # Clear mocks before each test
  clear_mocks

  # Load context
  load_context "frontend/deployment/tests/resources/context.json"

  # Override hosted zone ID with the one created in setup_file
  override_context "providers.cloud-providers.networking.hosted_public_zone_id" "$HOSTED_ZONE_ID"

  # Export common environment variables
  export NETWORK_LAYER="route53"
  export DISTRIBUTION_LAYER="cloudfront"
  export TOFU_PROVIDER="aws"
  export TOFU_PROVIDER_BUCKET="tofu-state-bucket"
  export TOFU_LOCK_TABLE="tofu-locks"
  export AWS_REGION="us-east-1"
  export SERVICE_PATH="$INTEGRATION_MODULE_ROOT/frontend"

  # Point to LocalStack-compatible modules
  export CUSTOM_TOFU_MODULES="$BATS_TEST_DIRNAME/localstack"
}

# =============================================================================
# Test: Create Infrastructure
# =============================================================================

@test "create infrastructure deploys S3, CloudFront, and Route53 resources" {
  # Setup API mocks for np CLI calls
  # Note: /token is automatically mocked by clear_mocks()
  local mocks_dir="frontend/deployment/tests/integration/mocks/asset_repository"

  # Mock the np CLI internal API calls
  mock_request "GET" "/category" "$mocks_dir/category.json"
  mock_request "GET" "/provider_specification" "$mocks_dir/list_provider_spec.json"
  mock_request "GET" "/provider" "$mocks_dir/list_provider.json"
  mock_request "GET" "/provider/s3-asset-repository-id" "$mocks_dir/get_provider.json"

  # Run the initial workflow
  run_workflow "frontend/deployment/workflows/initial.yaml"

  # Verify resources were created
  assert_s3_bucket_exists "assets-bucket"
  assert_cloudfront_exists "Distribution for automation-development-tools-7"
  assert_route53_record_exists "automation-development-tools.frontend.publicdomain.com" "A"
}

# =============================================================================
# Test: Destroy Infrastructure
# =============================================================================

#@test "destroy infrastructure removes CloudFront and Route53 resources" {
#  # Setup API mocks
#  mock_request "GET" "/provider" "frontend/deployment/tests/integration/mocks/asset_repository/success.json"
#
#  mock_request "GET" "/scope/7" 200 '{
#    "id": 7,
#    "name": "development-tools",
#    "slug": "development-tools"
#  }'
#
#  # Disable CloudFront before deletion (required by AWS)
#  if [[ -f "$BATS_TEST_DIRNAME/scripts/disable_cloudfront.sh" ]]; then
#    "$BATS_TEST_DIRNAME/scripts/disable_cloudfront.sh" "Distribution for automation-development-tools-7"
#  fi
#
#  # Run the delete workflow
#  run_workflow "frontend/deployment/workflows/delete.yaml"
#
#  # Verify resources were removed (S3 bucket should remain)
#  assert_s3_bucket_exists "assets-bucket"
#  assert_cloudfront_not_exists "Distribution for automation-development-tools-7"
#  assert_route53_record_not_exists "automation-development-tools.frontend.publicdomain.com" "A"
#}
