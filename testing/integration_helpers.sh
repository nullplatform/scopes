#!/bin/bash
# =============================================================================
# Integration Test Helpers for BATS
#
# Provides helper functions for integration testing with cloud provider support.
#
# Usage in BATS test files:
#   setup_file() {
#     load "${PROJECT_ROOT}/testing/integration_helpers.sh"
#     integration_setup --cloud-provider aws
#   }
#
#   teardown_file() {
#     integration_teardown
#   }
#
# Supported cloud providers: aws, azure, gcp
# =============================================================================

# =============================================================================
# Colors
# =============================================================================
INTEGRATION_RED='\033[0;31m'
INTEGRATION_GREEN='\033[0;32m'
INTEGRATION_YELLOW='\033[1;33m'
INTEGRATION_CYAN='\033[0;36m'
INTEGRATION_NC='\033[0m'

# =============================================================================
# Global State
# =============================================================================
INTEGRATION_CLOUD_PROVIDER="${INTEGRATION_CLOUD_PROVIDER:-}"
INTEGRATION_COMPOSE_FILE="${INTEGRATION_COMPOSE_FILE:-}"

# Determine module root from test file location if not already set
# Assumes test is at: <module>/<submodule>/tests/integration/<test>.bats
if [[ -z "${INTEGRATION_MODULE_ROOT:-}" ]]; then
  if [[ -n "${BATS_TEST_FILENAME:-}" ]]; then
    INTEGRATION_MODULE_ROOT=$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." 2>/dev/null && pwd) || INTEGRATION_MODULE_ROOT="${PROJECT_ROOT:-.}"
  else
    INTEGRATION_MODULE_ROOT="${PROJECT_ROOT:-.}"
  fi
fi
export INTEGRATION_MODULE_ROOT

# Default AWS/LocalStack configuration (can be overridden)
export LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
export MOTO_ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5555}"
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-$LOCALSTACK_ENDPOINT}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_PAGER=""

# Smocker configuration for API mocking
export SMOCKER_HOST="${SMOCKER_HOST:-http://localhost:8081}"

# =============================================================================
# Setup & Teardown
# =============================================================================

integration_setup() {
  local cloud_provider=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --cloud-provider)
        cloud_provider="$2"
        shift 2
        ;;
      *)
        echo -e "${INTEGRATION_RED}Unknown argument: $1${INTEGRATION_NC}"
        return 1
        ;;
    esac
  done

  # Validate cloud provider
  if [[ -z "$cloud_provider" ]]; then
    echo -e "${INTEGRATION_RED}Error: --cloud-provider is required${INTEGRATION_NC}"
    echo "Usage: integration_setup --cloud-provider <aws|azure|gcp>"
    return 1
  fi

  case "$cloud_provider" in
    aws|azure|gcp)
      INTEGRATION_CLOUD_PROVIDER="$cloud_provider"
      ;;
    *)
      echo -e "${INTEGRATION_RED}Error: Unsupported cloud provider: $cloud_provider${INTEGRATION_NC}"
      echo "Supported providers: aws, azure, gcp"
      return 1
      ;;
  esac

  export INTEGRATION_CLOUD_PROVIDER

  # Find docker-compose.yml
  INTEGRATION_COMPOSE_FILE=$(find_compose_file)
  export INTEGRATION_COMPOSE_FILE

  echo -e "${INTEGRATION_CYAN}Integration Setup${INTEGRATION_NC}"
  echo "  Cloud Provider: $INTEGRATION_CLOUD_PROVIDER"
  echo "  Module Root: $INTEGRATION_MODULE_ROOT"
  echo ""

  # Call provider-specific setup
  case "$INTEGRATION_CLOUD_PROVIDER" in
    aws)
      _setup_aws
      ;;
    azure)
      _setup_azure
      ;;
    gcp)
      _setup_gcp
      ;;
  esac
}

integration_teardown() {
  echo ""
  echo -e "${INTEGRATION_CYAN}Integration Teardown${INTEGRATION_NC}"

  # Call provider-specific teardown
  case "$INTEGRATION_CLOUD_PROVIDER" in
    aws)
      _teardown_aws
      ;;
    azure)
      _teardown_azure
      ;;
    gcp)
      _teardown_gcp
      ;;
  esac
}

# =============================================================================
# AWS Provider (LocalStack + Moto)
# =============================================================================

_setup_aws() {
  echo "  LocalStack: $LOCALSTACK_ENDPOINT"
  echo "  Moto: $MOTO_ENDPOINT"
  echo ""

  # Configure OpenTofu/Terraform S3 backend for LocalStack
  # These settings allow the S3 backend to work with LocalStack's S3 emulation
  export TOFU_INIT_VARIABLES="${TOFU_INIT_VARIABLES:-}"
  TOFU_INIT_VARIABLES="$TOFU_INIT_VARIABLES -backend-config=force_path_style=true"
  TOFU_INIT_VARIABLES="$TOFU_INIT_VARIABLES -backend-config=skip_credentials_validation=true"
  TOFU_INIT_VARIABLES="$TOFU_INIT_VARIABLES -backend-config=skip_metadata_api_check=true"
  TOFU_INIT_VARIABLES="$TOFU_INIT_VARIABLES -backend-config=skip_region_validation=true"
  TOFU_INIT_VARIABLES="$TOFU_INIT_VARIABLES -backend-config=endpoints={s3=\"$LOCALSTACK_ENDPOINT\",dynamodb=\"$LOCALSTACK_ENDPOINT\"}"
  export TOFU_INIT_VARIABLES

  # Start containers if compose file exists
  if [[ -n "$INTEGRATION_COMPOSE_FILE" ]]; then
    _start_localstack
  else
    echo -e "${INTEGRATION_YELLOW}Warning: No docker-compose.yml found, skipping container startup${INTEGRATION_NC}"
  fi
}

_teardown_aws() {
  if [[ -n "$INTEGRATION_COMPOSE_FILE" ]]; then
    _stop_localstack
  fi
}

_start_localstack() {
  echo -e "  Starting LocalStack..."
  docker compose -f "$INTEGRATION_COMPOSE_FILE" up -d 2>/dev/null

  echo -n "  Waiting for LocalStack to be ready"
  local max_attempts=30
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    if curl -s "$LOCALSTACK_ENDPOINT/_localstack/health" 2>/dev/null | jq -e '.services.s3 == "running"' > /dev/null 2>&1; then
      echo ""
      echo -e "  ${INTEGRATION_GREEN}LocalStack is ready${INTEGRATION_NC}"
      echo ""
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
    echo -n "."
  done

  echo ""
  echo -e "  ${INTEGRATION_RED}LocalStack failed to start${INTEGRATION_NC}"
  return 1
}

_stop_localstack() {
  echo "  Stopping LocalStack..."
  docker compose -f "$INTEGRATION_COMPOSE_FILE" down -v 2>/dev/null || true
}

# =============================================================================
# Azure Provider (Azurite) - Placeholder
# =============================================================================

_setup_azure() {
  echo -e "${INTEGRATION_YELLOW}Azure provider setup not yet implemented${INTEGRATION_NC}"
  echo "  Azurite endpoint would be configured here"
  echo ""
}

_teardown_azure() {
  echo -e "${INTEGRATION_YELLOW}Azure provider teardown not yet implemented${INTEGRATION_NC}"
}

# =============================================================================
# GCP Provider (Fake GCS Server) - Placeholder
# =============================================================================

_setup_gcp() {
  echo -e "${INTEGRATION_YELLOW}GCP provider setup not yet implemented${INTEGRATION_NC}"
  echo "  Fake GCS Server endpoint would be configured here"
  echo ""
}

_teardown_gcp() {
  echo -e "${INTEGRATION_YELLOW}GCP provider teardown not yet implemented${INTEGRATION_NC}"
}

# =============================================================================
# Utility Functions
# =============================================================================

find_compose_file() {
  local search_paths=(
    "${BATS_TEST_DIRNAME:-}/docker-compose.yml"
    "${BATS_TEST_DIRNAME:-}/../docker-compose.yml"
    "${INTEGRATION_MODULE_ROOT}/tests/integration/docker-compose.yml"
  )

  for path in "${search_paths[@]}"; do
    if [[ -f "$path" ]]; then
      echo "$path"
      return 0
    fi
  done

  # Return success with empty output - compose file is optional
  # (containers may already be managed by the test runner)
  return 0
}

# =============================================================================
# AWS Local Commands
# =============================================================================

# Execute AWS CLI against LocalStack
aws_local() {
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" --no-cli-pager --no-cli-auto-prompt "$@"
}

# Execute AWS CLI against Moto (for CloudFront)
aws_moto() {
  aws --endpoint-url="$MOTO_ENDPOINT" --no-cli-pager --no-cli-auto-prompt "$@"
}

# =============================================================================
# Workflow Execution
# =============================================================================

# Run a nullplatform workflow
# Usage: run_workflow "deployment/workflows/initial.yaml"
run_workflow() {
  local workflow="$1"
  local full_path

  # Resolve path relative to module root
  if [[ "$workflow" = /* ]]; then
    full_path="$workflow"
  else
    full_path="$INTEGRATION_MODULE_ROOT/$workflow"
  fi

  echo -e "${INTEGRATION_CYAN}Running workflow:${INTEGRATION_NC} $workflow"
  np service workflow exec --workflow "$full_path"
}

# =============================================================================
# Context Helpers
# =============================================================================

# Load context from a JSON file
# Usage: load_context "resources/context.json"
load_context() {
  local context_file="$1"
  local full_path

  # Resolve path relative to module root
  if [[ "$context_file" = /* ]]; then
    full_path="$context_file"
  else
    full_path="$INTEGRATION_MODULE_ROOT/$context_file"
  fi

  if [[ ! -f "$full_path" ]]; then
    echo -e "${INTEGRATION_RED}Context file not found: $full_path${INTEGRATION_NC}"
    return 1
  fi

  export CONTEXT=$(cat "$full_path")
  echo -e "  ${INTEGRATION_CYAN}Loaded context from:${INTEGRATION_NC} $context_file"
}

# Override a value in the current CONTEXT
# Usage: override_context "providers.networking.zone_id" "Z1234567890"
override_context() {
  local key="$1"
  local value="$2"

  if [[ -z "$CONTEXT" ]]; then
    echo -e "${INTEGRATION_RED}Error: CONTEXT is not set. Call load_context first.${INTEGRATION_NC}"
    return 1
  fi

  CONTEXT=$(echo "$CONTEXT" | jq --arg k "$key" --arg v "$value" 'setpath($k | split("."); $v)')
  export CONTEXT
}

# =============================================================================
# AWS Assertions
# =============================================================================

_assert_result() {
  local success="$1"
  if [[ "$success" == "true" ]]; then
    echo -e "${INTEGRATION_GREEN}PASS${INTEGRATION_NC}"
    return 0
  else
    echo -e "${INTEGRATION_RED}FAIL${INTEGRATION_NC}"
    return 1
  fi
}

# Assert S3 bucket exists
# Usage: assert_s3_bucket_exists "my-bucket"
assert_s3_bucket_exists() {
  local bucket="$1"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} S3 bucket '${bucket}' exists ... "

  if aws_local s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Assert S3 bucket does not exist
# Usage: assert_s3_bucket_not_exists "my-bucket"
assert_s3_bucket_not_exists() {
  local bucket="$1"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} S3 bucket '${bucket}' does not exist ... "

  if aws_local s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    _assert_result "false"
    return 1
  else
    _assert_result "true"
  fi
}

# Assert CloudFront distribution exists (by comment)
# Usage: assert_cloudfront_exists "My Distribution Comment"
assert_cloudfront_exists() {
  local comment="$1"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} CloudFront distribution '${comment}' exists ... "

  local distribution
  distribution=$(aws_moto cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='$comment'].Id" \
    --output text 2>/dev/null)

  if [[ -n "$distribution" ]] && [[ "$distribution" != "None" ]]; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Assert CloudFront distribution does not exist (by comment)
# Usage: assert_cloudfront_not_exists "My Distribution Comment"
assert_cloudfront_not_exists() {
  local comment="$1"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} CloudFront distribution '${comment}' does not exist ... "

  local distribution
  distribution=$(aws_moto cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='$comment'].Id" \
    --output text 2>/dev/null)

  if [[ -z "$distribution" ]] || [[ "$distribution" == "None" ]]; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Assert Route53 record exists
# Usage: assert_route53_record_exists "myapp.example.com" "A"
assert_route53_record_exists() {
  local record_name="$1"
  local record_type="$2"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} Route53 ${record_type} record '${record_name}' exists ... "

  # Ensure record name ends with a dot
  [[ "$record_name" != *. ]] && record_name="$record_name."

  # Get the first hosted zone
  local zone_id
  zone_id=$(aws_local route53 list-hosted-zones \
    --query "HostedZones[0].Id" \
    --output text 2>/dev/null | sed 's|/hostedzone/||')

  if [[ -z "$zone_id" ]] || [[ "$zone_id" == "None" ]]; then
    _assert_result "false"
    echo "    No Route53 hosted zones found"
    return 1
  fi

  local record
  record=$(aws_local route53 list-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Name=='$record_name' && Type=='$record_type']" \
    --output text 2>/dev/null)

  if [[ -n "$record" ]] && [[ "$record" != "None" ]]; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Assert Route53 record does not exist
# Usage: assert_route53_record_not_exists "myapp.example.com" "A"
assert_route53_record_not_exists() {
  local record_name="$1"
  local record_type="$2"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} Route53 ${record_type} record '${record_name}' does not exist ... "

  # Ensure record name ends with a dot
  [[ "$record_name" != *. ]] && record_name="$record_name."

  # Get the first hosted zone
  local zone_id
  zone_id=$(aws_local route53 list-hosted-zones \
    --query "HostedZones[0].Id" \
    --output text 2>/dev/null | sed 's|/hostedzone/||')

  if [[ -z "$zone_id" ]] || [[ "$zone_id" == "None" ]]; then
    # No zones means no records
    _assert_result "true"
    return 0
  fi

  local record
  record=$(aws_local route53 list-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Name=='$record_name' && Type=='$record_type']" \
    --output text 2>/dev/null)

  if [[ -z "$record" ]] || [[ "$record" == "None" ]]; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Assert DynamoDB table exists
# Usage: assert_dynamodb_table_exists "my-table"
assert_dynamodb_table_exists() {
  local table="$1"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} DynamoDB table '${table}' exists ... "

  if aws_local dynamodb describe-table --table-name "$table" >/dev/null 2>&1; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Assert DynamoDB table does not exist
# Usage: assert_dynamodb_table_not_exists "my-table"
assert_dynamodb_table_not_exists() {
  local table="$1"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} DynamoDB table '${table}' does not exist ... "

  if aws_local dynamodb describe-table --table-name "$table" >/dev/null 2>&1; then
    _assert_result "false"
    return 1
  else
    _assert_result "true"
  fi
}

# =============================================================================
# Generic Assertions
# =============================================================================

# Assert command succeeds
# Usage: assert_success "aws s3 ls"
assert_success() {
  local cmd="$1"
  local description="${2:-Command succeeds}"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} ${description} ... "

  if eval "$cmd" >/dev/null 2>&1; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Assert command fails
# Usage: assert_failure "aws s3api head-bucket --bucket nonexistent"
assert_failure() {
  local cmd="$1"
  local description="${2:-Command fails}"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} ${description} ... "

  if eval "$cmd" >/dev/null 2>&1; then
    _assert_result "false"
    return 1
  else
    _assert_result "true"
  fi
}

# Assert output contains string
# Usage: result=$(some_command); assert_contains "$result" "expected"
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="${3:-Output contains '$needle'}"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} ${description} ... "

  if [[ "$haystack" == *"$needle"* ]]; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Assert values are equal
# Usage: assert_equals "$actual" "$expected" "Values match"
assert_equals() {
  local actual="$1"
  local expected="$2"
  local description="${3:-Values are equal}"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} ${description} ... "

  if [[ "$actual" == "$expected" ]]; then
    _assert_result "true"
  else
    _assert_result "false"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
    return 1
  fi
}

# =============================================================================
# API Mocking (Smocker)
#
# Smocker is used to mock the nullplatform API (api.nullplatform.com).
# Tests run in a container where api.nullplatform.com resolves to smocker.
# =============================================================================

# Clear all mocks from smocker and set up default mocks
# Usage: clear_mocks
clear_mocks() {
  curl -s -X POST "${SMOCKER_HOST}/reset" >/dev/null 2>&1
  # Set up default mocks that are always needed
  _setup_default_mocks
}

# Set up default mocks that are always needed for np CLI
# These are internal API calls that np CLI makes automatically
_setup_default_mocks() {
  # Token endpoint - np CLI always authenticates before making API calls
  local token_mock
  token_mock=$(cat <<'EOF'
[{
  "request": {
    "method": "POST",
    "path": "/token"
  },
  "response": {
    "status": 200,
    "headers": {"Content-Type": "application/json"},
    "body": "{\"access_token\": \"test-integration-token\", \"token_type\": \"Bearer\", \"expires_in\": 3600}"
  }
}]
EOF
)
  curl -s -X POST "${SMOCKER_HOST}/mocks" \
    -H "Content-Type: application/json" \
    -d "$token_mock" >/dev/null 2>&1
}

# Mock an API request
# Usage with file:   mock_request "GET" "/providers/123" "responses/provider.json"
# Usage inline:      mock_request "POST" "/deployments" 201 '{"id": "new-dep"}'
#
# File format (JSON):
# {
#   "status": 200,
#   "headers": {"Content-Type": "application/json"},  // optional
#   "body": { ... }
# }
mock_request() {
  local method="$1"
  local path="$2"
  local status_or_file="$3"
  local body="$4"

  local status
  local response_body
  local headers='{"Content-Type": "application/json"}'

  # Check if third argument is a file or a status code
  if [[ -f "$status_or_file" ]]; then
    # File mode - read status and body from file
    local file_content
    file_content=$(cat "$status_or_file")
    status=$(echo "$file_content" | jq -r '.status // 200')
    response_body=$(echo "$file_content" | jq -c '.body // {}')
    local file_headers
    file_headers=$(echo "$file_content" | jq -c '.headers // null')
    if [[ "$file_headers" != "null" ]]; then
      headers="$file_headers"
    fi
  elif [[ -f "${INTEGRATION_MODULE_ROOT}/$status_or_file" ]]; then
    # File mode with relative path
    local file_content
    file_content=$(cat "${INTEGRATION_MODULE_ROOT}/$status_or_file")
    status=$(echo "$file_content" | jq -r '.status // 200')
    response_body=$(echo "$file_content" | jq -c '.body // {}')
    local file_headers
    file_headers=$(echo "$file_content" | jq -c '.headers // null')
    if [[ "$file_headers" != "null" ]]; then
      headers="$file_headers"
    fi
  else
    # Inline mode - status code and body provided directly
    status="$status_or_file"
    response_body="$body"
  fi

  # Build smocker mock definition
  # Note: Smocker expects body as a string, not a JSON object
  local mock_definition
  mock_definition=$(jq -n \
    --arg method "$method" \
    --arg path "$path" \
    --argjson status "$status" \
    --arg body "$response_body" \
    --argjson headers "$headers" \
    '[{
      "request": {
        "method": $method,
        "path": $path
      },
      "response": {
        "status": $status,
        "headers": $headers,
        "body": $body
      }
    }]')

  # Register mock with smocker
  local result
  local http_code
  http_code=$(curl -s -w "%{http_code}" -o /tmp/smocker_response.json -X POST "${SMOCKER_HOST}/mocks" \
    -H "Content-Type: application/json" \
    -d "$mock_definition" 2>&1)
  result=$(cat /tmp/smocker_response.json 2>/dev/null)

  if [[ "$http_code" != "200" ]]; then
    local error_msg
    error_msg=$(echo "$result" | jq -r '.message // "Unknown error"' 2>/dev/null)
    echo -e "${INTEGRATION_RED}Failed to register mock (HTTP ${http_code}): ${error_msg}${INTEGRATION_NC}"
    return 1
  fi

  echo -e "  ${INTEGRATION_CYAN}Mock:${INTEGRATION_NC} ${method} ${path} -> ${status}"
}

# Mock a request with query parameters
# Usage: mock_request_with_query "GET" "/providers" "type=assets-repository" 200 '[...]'
mock_request_with_query() {
  local method="$1"
  local path="$2"
  local query="$3"
  local status="$4"
  local body="$5"

  local mock_definition
  mock_definition=$(jq -n \
    --arg method "$method" \
    --arg path "$path" \
    --arg query "$query" \
    --argjson status "$status" \
    --arg body "$body" \
    '[{
      "request": {
        "method": $method,
        "path": $path,
        "query_params": ($query | split("&") | map(split("=") | {(.[0]): [.[1]]}) | add)
      },
      "response": {
        "status": $status,
        "headers": {"Content-Type": "application/json"},
        "body": $body
      }
    }]')

  curl -s -X POST "${SMOCKER_HOST}/mocks" \
    -H "Content-Type: application/json" \
    -d "$mock_definition" >/dev/null 2>&1

  echo -e "  ${INTEGRATION_CYAN}Mock:${INTEGRATION_NC} ${method} ${path}?${query} -> ${status}"
}

# Verify that a mock was called
# Usage: assert_mock_called "GET" "/providers/123"
assert_mock_called() {
  local method="$1"
  local path="$2"
  echo -ne "  ${INTEGRATION_CYAN}Assert:${INTEGRATION_NC} ${method} ${path} was called ... "

  local history
  history=$(curl -s "${SMOCKER_HOST}/history" 2>/dev/null)

  local called
  called=$(echo "$history" | jq -r \
    --arg method "$method" \
    --arg path "$path" \
    '[.[] | select(.request.method == $method and .request.path == $path)] | length')

  if [[ "$called" -gt 0 ]]; then
    _assert_result "true"
  else
    _assert_result "false"
    return 1
  fi
}

# Get the number of times a mock was called
# Usage: count=$(mock_call_count "GET" "/providers/123")
mock_call_count() {
  local method="$1"
  local path="$2"

  local history
  history=$(curl -s "${SMOCKER_HOST}/history" 2>/dev/null)

  echo "$history" | jq -r \
    --arg method "$method" \
    --arg path "$path" \
    '[.[] | select(.request.method == $method and .request.path == $path)] | length'
}

# =============================================================================
# Help / Documentation
# =============================================================================

# Display help for all available integration test utilities
test_help() {
  cat <<'EOF'
================================================================================
                    Integration Test Helpers Reference
================================================================================

SETUP & TEARDOWN
----------------
  integration_setup --cloud-provider <aws|azure|gcp>
      Initialize integration test environment for the specified cloud provider.
      Call this in setup_file().

  integration_teardown
      Clean up integration test environment.
      Call this in teardown_file().

AWS LOCAL COMMANDS
------------------
  aws_local <aws-cli-args>
      Execute AWS CLI against LocalStack (S3, Route53, DynamoDB, etc.)
      Example: aws_local s3 ls

  aws_moto <aws-cli-args>
      Execute AWS CLI against Moto (CloudFront)
      Example: aws_moto cloudfront list-distributions

WORKFLOW EXECUTION
------------------
  run_workflow "<path/to/workflow.yaml>"
      Run a nullplatform workflow file.
      Path is relative to module root.
      Example: run_workflow "frontend/deployment/workflows/initial.yaml"

CONTEXT HELPERS
---------------
  load_context "<path/to/context.json>"
      Load a context JSON file into the CONTEXT environment variable.
      Example: load_context "tests/resources/context.json"

  override_context "<json.path>" "<value>"
      Override a value in the current CONTEXT.
      Example: override_context "providers.networking.zone_id" "Z1234567890"

API MOCKING (Smocker)
---------------------
  clear_mocks
      Clear all mocks and set up default mocks (token endpoint).
      Call this at the start of each test.

  mock_request "<METHOD>" "<path>" "<file.json>"
      Mock an API request using a response file.
      File format: { "status": 200, "body": {...} }
      Example: mock_request "GET" "/provider/123" "mocks/provider.json"

  mock_request "<METHOD>" "<path>" <status> '<json-body>'
      Mock an API request with inline response.
      Example: mock_request "POST" "/deployments" 201 '{"id": "new"}'

  mock_request_with_query "<METHOD>" "<path>" "<query>" <status> '<body>'
      Mock a request with query parameters.
      Example: mock_request_with_query "GET" "/items" "type=foo" 200 '[...]'

  assert_mock_called "<METHOD>" "<path>"
      Assert that a mock endpoint was called.
      Example: assert_mock_called "GET" "/provider/123"

  mock_call_count "<METHOD>" "<path>"
      Get the number of times a mock was called.
      Example: count=$(mock_call_count "GET" "/provider/123")

AWS ASSERTIONS
--------------
  assert_s3_bucket_exists "<bucket-name>"
      Assert an S3 bucket exists in LocalStack.

  assert_s3_bucket_not_exists "<bucket-name>"
      Assert an S3 bucket does not exist.

  assert_cloudfront_exists "<distribution-comment>"
      Assert a CloudFront distribution exists (matched by comment).

  assert_cloudfront_not_exists "<distribution-comment>"
      Assert a CloudFront distribution does not exist.

  assert_route53_record_exists "<record-name>" "<type>"
      Assert a Route53 record exists.
      Example: assert_route53_record_exists "app.example.com" "A"

  assert_route53_record_not_exists "<record-name>" "<type>"
      Assert a Route53 record does not exist.

  assert_dynamodb_table_exists "<table-name>"
      Assert a DynamoDB table exists.

  assert_dynamodb_table_not_exists "<table-name>"
      Assert a DynamoDB table does not exist.

GENERIC ASSERTIONS
------------------
  assert_success "<command>" ["<description>"]
      Assert a command succeeds (exit code 0).

  assert_failure "<command>" ["<description>"]
      Assert a command fails (non-zero exit code).

  assert_contains "<haystack>" "<needle>" ["<description>"]
      Assert a string contains a substring.

  assert_equals "<actual>" "<expected>" ["<description>"]
      Assert two values are equal.

ENVIRONMENT VARIABLES
---------------------
  LOCALSTACK_ENDPOINT    LocalStack URL (default: http://localhost:4566)
  MOTO_ENDPOINT          Moto URL (default: http://localhost:5555)
  SMOCKER_HOST           Smocker admin URL (default: http://localhost:8081)
  AWS_ENDPOINT_URL       AWS endpoint for CLI (default: $LOCALSTACK_ENDPOINT)
  INTEGRATION_MODULE_ROOT   Root directory of the module being tested

================================================================================
EOF
}
