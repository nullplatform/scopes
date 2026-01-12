#!/bin/bash
# =============================================================================
# Integration test utilities for shunit2
#
# Provides helper functions for:
#   - LocalStack management
#   - AWS resource assertions
#   - Test configuration loading
#   - Workflow execution
#
# Usage:
#   export INTEGRATION_TEST_DIR="/path/to/integration/test/dir"
#   source "/path/to/tests/integration_test_utils.sh"
# =============================================================================

# Validate INTEGRATION_TEST_DIR is set
if [ -z "${INTEGRATION_TEST_DIR:-}" ]; then
  echo "Error: INTEGRATION_TEST_DIR must be set before sourcing integration_test_utils.sh"
  exit 1
fi

export INTEGRATION_TEST_DIR
export PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# LocalStack configuration (S3, Route53, DynamoDB, IAM, STS, ACM)
export LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
# Moto configuration (CloudFront)
export MOTO_ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5555}"
export AWS_ENDPOINT_URL="$LOCALSTACK_ENDPOINT"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_PAGER=""

# Save original PATH before adding mock
export NP_ORIGINAL_PATH="$PATH"

# Add mock np to PATH
export PATH="$INTEGRATION_TEST_DIR/mocks:$PATH"

# =============================================================================
# LocalStack Management
# =============================================================================

localstack_start() {
  echo "Starting LocalStack..."
  docker compose -f "$INTEGRATION_TEST_DIR/docker-compose.yml" up -d
  localstack_wait_ready
}

localstack_stop() {
  echo "Stopping LocalStack..."
  docker compose -f "$INTEGRATION_TEST_DIR/docker-compose.yml" down -v
}

localstack_wait_ready() {
  echo "Waiting for LocalStack to be ready..."
  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if curl -s "$LOCALSTACK_ENDPOINT/_localstack/health" | jq -e '.services.s3 == "running"' > /dev/null 2>&1; then
      echo "LocalStack is ready"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done

  echo "LocalStack failed to start"
  return 1
}

localstack_reset() {
  echo "Resetting LocalStack state..."
  # Reset by restarting the container
  docker compose -f "$INTEGRATION_TEST_DIR/docker-compose.yml" restart localstack
  localstack_wait_ready
}

# =============================================================================
# Test Configuration
# =============================================================================

load_test_config() {
  local config_file="$1"

  if [ ! -f "$config_file" ]; then
    echo "Error: Config file not found: $config_file"
    return 1
  fi

  export CURRENT_TEST_CONFIG="$config_file"
  export CURRENT_TEST_NAME=$(jq -r '.name' "$config_file")
  export CURRENT_TEST_STEPS=$(jq -r '.steps | length' "$config_file")

  # Setup prerequisites
  setup_prerequisites
}

# =============================================================================
# Prerequisites Setup (S3 buckets, Route53 zones, etc.)
# =============================================================================

setup_prerequisites() {
  echo ""
  echo "=========================================="
  echo "Setting up prerequisites"
  echo "=========================================="

  # Get setup commands array
  local setup_commands=$(jq -r '.setup // []' "$CURRENT_TEST_CONFIG")
  local cmd_count=$(echo "$setup_commands" | jq -r 'length')

  if [ "$cmd_count" -eq 0 ]; then
    echo "No setup commands defined"
    echo ""
    return 0
  fi

  echo "Running $cmd_count setup command(s)..."
  echo ""

  for i in $(seq 0 $((cmd_count - 1))); do
    local cmd=$(echo "$setup_commands" | jq -r ".[$i]")
    echo "  $ $cmd"

    # Execute the command
    eval "$cmd" </dev/null 2>/dev/null || true
  done

  echo ""
  echo "Prerequisites setup complete"
  echo ""
}

get_step_config() {
  local step_index="$1"
  jq -r ".steps[$step_index]" "$CURRENT_TEST_CONFIG"
}

get_step_env() {
  local step_index="$1"
  jq -r ".steps[$step_index].env // {}" "$CURRENT_TEST_CONFIG"
}

get_step_workflow() {
  local step_index="$1"
  jq -r ".steps[$step_index].workflow" "$CURRENT_TEST_CONFIG"
}

get_step_assertions() {
  local step_index="$1"
  jq -r ".steps[$step_index].assertions // []" "$CURRENT_TEST_CONFIG"
}

# =============================================================================
# Workflow Execution
# =============================================================================

setup_test_environment() {
  local step_index="$1"

  # Set mock configuration
  export NP_MOCK_CONFIG="$CURRENT_TEST_CONFIG"
  export NP_MOCK_DIR="$INTEGRATION_TEST_DIR/mocks/responses"

  # Set AWS endpoint for LocalStack
  export AWS_ENDPOINT_URL="$LOCALSTACK_ENDPOINT"

  # Load CONTEXT from file if specified
  local context_file=$(jq -r ".steps[$step_index].context_file // .context_file // empty" "$CURRENT_TEST_CONFIG")
  if [ -n "$context_file" ]; then
    # Resolve relative paths from the tests directory
    if [[ "$context_file" != /* ]]; then
      context_file="$PROJECT_DIR/tests/$context_file"
    fi
    if [ -f "$context_file" ]; then
      echo "  Loading CONTEXT from: $context_file"
      export CONTEXT=$(cat "$context_file")
    else
      echo "  Warning: Context file not found: $context_file"
    fi
  fi

  # Apply context_overrides - allows dynamic values using shell commands
  local overrides=$(jq -r ".steps[$step_index].context_overrides // .context_overrides // {}" "$CURRENT_TEST_CONFIG")
  if [ "$overrides" != "{}" ] && [ -n "$CONTEXT" ]; then
    echo "  Applying context overrides..."
    local override_keys=$(echo "$overrides" | jq -r 'keys[]')
    for key in $override_keys; do
      local value_expr=$(echo "$overrides" | jq -r --arg k "$key" '.[$k]')
      # Evaluate shell commands in the value (e.g., $(aws ...))
      local value=$(eval "echo \"$value_expr\"")
      echo "    $key = $value"
      # Use jq to set nested keys (supports dot notation like "providers.cloud-providers.networking.hosted_public_zone_id")
      CONTEXT=$(echo "$CONTEXT" | jq --arg k "$key" --arg v "$value" 'setpath($k | split("."); $v)')
    done
    export CONTEXT
  fi

  # Load step-specific environment variables (with variable expansion)
  local env_json=$(get_step_env "$step_index")
  while IFS="=" read -r key value; do
    if [ -n "$key" ]; then
      # Expand environment variables in the value
      local expanded_value=$(eval "echo \"$value\"")
      export "$key=$expanded_value"
    fi
  done < <(echo "$env_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
}

run_workflow_step() {
  local step_index="$1"
  local workflow
  workflow=$(get_step_workflow "$step_index")
  # Expand environment variables in workflow path
  workflow=$(eval "echo \"$workflow\"")
  local step_name
  step_name=$(jq -r ".steps[$step_index].name" "$CURRENT_TEST_CONFIG")

  echo "Running step: $step_name"
  echo "Workflow: $workflow"
  echo ""

  # Update mock config to point to this step's mocks
  export NP_MOCK_STEP_INDEX="$step_index"

  # Execute the workflow using real np CLI
  # The mock will pass through 'np service workflow exec' to the real CLI
  np service workflow exec --workflow "$workflow"
}

# =============================================================================
# AWS Resource Assertions (against LocalStack)
# =============================================================================

aws_local() {
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" --no-cli-pager --no-cli-auto-prompt "$@"
}

assert_s3_bucket_exists() {
  local bucket="$1"

  echo -n "  Checking S3 bucket '$bucket' exists... "
  if aws_local s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    echo "✓"
    return 0
  else
    echo "✗"
    fail "S3 bucket does not exist: $bucket"
    return 1
  fi
}

assert_s3_bucket_not_exists() {
  local bucket="$1"

  echo -n "  Checking S3 bucket '$bucket' does not exist... "
  if aws_local s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    echo "✗"
    fail "S3 bucket should not exist: $bucket"
    return 1
  else
    echo "✓"
    return 0
  fi
}

assert_cloudfront_distribution_exists() {
  local comment="$1"

  echo -n "  Checking CloudFront distribution with comment '$comment' exists... "
  # CloudFront uses Moto endpoint, not LocalStack
  local distribution
  distribution=$(aws --endpoint-url="$MOTO_ENDPOINT" --no-cli-pager cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='$comment'].Id" \
    --output text 2>/dev/null)

  if [ -n "$distribution" ] && [ "$distribution" != "None" ]; then
    echo "✓"
    return 0
  else
    echo "✗"
    fail "CloudFront distribution does not exist with comment: $comment"
    return 1
  fi
}

assert_cloudfront_distribution_not_exists() {
  local comment="$1"

  echo -n "  Checking CloudFront distribution with comment '$comment' does not exist... "
  # CloudFront uses Moto endpoint, not LocalStack
  local distribution
  distribution=$(aws --endpoint-url="$MOTO_ENDPOINT" --no-cli-pager cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='$comment'].Id" \
    --output text 2>/dev/null)

  if [ -z "$distribution" ] || [ "$distribution" == "None" ]; then
    echo "✓"
    return 0
  else
    echo "✗"
    fail "CloudFront distribution should not exist with comment: $comment"
    return 1
  fi
}

assert_route53_record_exists() {
  local record_name="$1"
  local record_type="$2"

  echo -n "  Checking Route53 record '$record_name' ($record_type) exists... "

  # Ensure record name ends with a dot
  [[ "$record_name" != *. ]] && record_name="$record_name."

  # Get the first hosted zone
  local zone_id
  zone_id=$(aws_local route53 list-hosted-zones \
    --query "HostedZones[0].Id" \
    --output text 2>/dev/null | sed 's|/hostedzone/||')

  if [ -z "$zone_id" ] || [ "$zone_id" == "None" ]; then
    echo "✗"
    fail "No Route53 hosted zones found"
    return 1
  fi

  local record
  record=$(aws_local route53 list-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Name=='$record_name' && Type=='$record_type']" \
    --output text 2>/dev/null)

  if [ -n "$record" ] && [ "$record" != "None" ]; then
    echo "✓"
    return 0
  else
    echo "✗"
    fail "Route53 record does not exist: $record_name ($record_type) in zone $zone_id"
    return 1
  fi
}

assert_route53_record_not_exists() {
  local record_name="$1"
  local record_type="$2"

  echo -n "  Checking Route53 record '$record_name' ($record_type) does not exist... "

  # Ensure record name ends with a dot
  [[ "$record_name" != *. ]] && record_name="$record_name."

  # Get the first hosted zone
  local zone_id
  zone_id=$(aws_local route53 list-hosted-zones \
    --query "HostedZones[0].Id" \
    --output text 2>/dev/null | sed 's|/hostedzone/||')

  if [ -z "$zone_id" ] || [ "$zone_id" == "None" ]; then
    # No zones means no records, so assertion passes
    echo "✓"
    return 0
  fi

  local record
  record=$(aws_local route53 list-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Name=='$record_name' && Type=='$record_type']" \
    --output text 2>/dev/null)

  if [ -z "$record" ] || [ "$record" == "None" ]; then
    echo "✓"
    return 0
  else
    echo "✗"
    fail "Route53 record should not exist: $record_name ($record_type) in zone $zone_id"
    return 1
  fi
}

# =============================================================================
# Assertion Runner
# =============================================================================

run_assertions() {
  local step_index="$1"
  local assertions=$(get_step_assertions "$step_index")
  local assertion_count=$(echo "$assertions" | jq -r 'length')

  echo "Running $assertion_count assertions..."

  for i in $(seq 0 $((assertion_count - 1))); do
    local assertion=$(echo "$assertions" | jq -r ".[$i]")
    local type=$(echo "$assertion" | jq -r '.type')

    case "$type" in
      s3_bucket_exists)
        local bucket=$(echo "$assertion" | jq -r '.bucket')
        assert_s3_bucket_exists "$bucket"
        ;;
      s3_bucket_not_exists)
        local bucket=$(echo "$assertion" | jq -r '.bucket')
        assert_s3_bucket_not_exists "$bucket"
        ;;
      cloudfront_distribution_exists)
        local comment=$(echo "$assertion" | jq -r '.comment')
        assert_cloudfront_distribution_exists "$comment"
        ;;
      cloudfront_distribution_not_exists)
        local comment=$(echo "$assertion" | jq -r '.comment')
        assert_cloudfront_distribution_not_exists "$comment"
        ;;
      route53_record_exists)
        local name=$(echo "$assertion" | jq -r '.name')
        local record_type=$(echo "$assertion" | jq -r '.record_type')
        assert_route53_record_exists "$name" "$record_type"
        ;;
      route53_record_not_exists)
        local name=$(echo "$assertion" | jq -r '.name')
        local record_type=$(echo "$assertion" | jq -r '.record_type')
        assert_route53_record_not_exists "$name" "$record_type"
        ;;
      *)
        fail "Unknown assertion type: $type"
        ;;
    esac
  done
}

# =============================================================================
# Full Test Step Execution
# =============================================================================

run_before_commands() {
  local step_index="$1"
  local before_commands
  before_commands=$(jq -r ".steps[$step_index].before // []" "$CURRENT_TEST_CONFIG")
  local cmd_count
  cmd_count=$(echo "$before_commands" | jq -r 'length')

  if [ "$cmd_count" -eq 0 ]; then
    return 0
  fi

  echo "Running $cmd_count before command(s)..."
  echo ""

  for i in $(seq 0 $((cmd_count - 1))); do
    local cmd
    cmd=$(echo "$before_commands" | jq -r ".[$i]")
    echo "  $ $cmd"
    eval "$cmd" || true
  done

  echo ""
}

execute_test_step() {
  local step_index="$1"
  local step_name
  step_name=$(jq -r ".steps[$step_index].name" "$CURRENT_TEST_CONFIG")

  echo ""
  echo "=========================================="
  echo "Step $((step_index + 1)): $step_name"
  echo "=========================================="

  # Setup environment for this step
  setup_test_environment "$step_index"

  # Run before commands (if any)
  run_before_commands "$step_index"

  # Run the workflow
  run_workflow_step "$step_index"

  # Run assertions
  run_assertions "$step_index"

  echo "Step $step_name completed successfully"
}

execute_all_steps() {
  local step_count=$(jq -r '.steps | length' "$CURRENT_TEST_CONFIG")

  for i in $(seq 0 $((step_count - 1))); do
    execute_test_step "$i"
  done
}
