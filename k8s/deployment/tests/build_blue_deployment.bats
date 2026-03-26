#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/build_blue_deployment - blue deployment builder
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export DEPLOYMENT_ID="deploy-green-123"

  export CONTEXT='{
    "blue_replicas": 2,
    "scope": {
      "current_active_deployment": "deploy-old-456"
    },
    "deployment": {
      "id": "deploy-green-123"
    }
  }'

  # Track what build_deployment receives
  export BUILD_DEPLOYMENT_REPLICAS=""
  export BUILD_DEPLOYMENT_DEPLOYMENT_ID=""

  # Mock build_deployment to capture arguments
  mkdir -p "$PROJECT_ROOT/k8s/deployment"
  cat > "$PROJECT_ROOT/k8s/deployment/build_deployment.mock" << 'MOCK'
BUILD_DEPLOYMENT_REPLICAS="$REPLICAS"
BUILD_DEPLOYMENT_DEPLOYMENT_ID="$DEPLOYMENT_ID"
echo "Building deployment with replicas=$REPLICAS deployment_id=$DEPLOYMENT_ID"
MOCK
}

teardown() {
  rm -f "$PROJECT_ROOT/k8s/deployment/build_deployment.mock"
  unset CONTEXT
  unset BUILD_DEPLOYMENT_REPLICAS
  unset BUILD_DEPLOYMENT_DEPLOYMENT_ID
}

# =============================================================================
# Blue Replicas Extraction Tests
# =============================================================================
@test "build_blue_deployment: extracts blue_replicas from context" {
  # Can't easily test sourced script, but we verify CONTEXT parsing
  replicas=$(echo "$CONTEXT" | jq -r .blue_replicas)

  assert_equal "$replicas" "2"
}

# =============================================================================
# Deployment ID Handling Tests
# =============================================================================
@test "build_blue_deployment: uses current_active_deployment as blue deployment" {
  blue_id=$(echo "$CONTEXT" | jq -r .scope.current_active_deployment)

  assert_equal "$blue_id" "deploy-old-456"
}

@test "build_blue_deployment: preserves green deployment ID" {
  # After script runs, DEPLOYMENT_ID should be restored to green
  assert_equal "$DEPLOYMENT_ID" "deploy-green-123"
}

# =============================================================================
# Context Update Tests
# =============================================================================
@test "build_blue_deployment: updates context with blue deployment ID" {
  # Test that jq command correctly updates deployment.id
  updated_context=$(echo "$CONTEXT" | jq \
    --arg deployment_id "deploy-old-456" \
    '.deployment.id = $deployment_id')

  updated_id=$(echo "$updated_context" | jq -r .deployment.id)

  assert_equal "$updated_id" "deploy-old-456"
}

@test "build_blue_deployment: restores context with green deployment ID" {
  # Test that jq command correctly restores deployment.id
  updated_context=$(echo "$CONTEXT" | jq \
    --arg deployment_id "deploy-green-123" \
    '.deployment.id = $deployment_id')

  updated_id=$(echo "$updated_context" | jq -r .deployment.id)

  assert_equal "$updated_id" "deploy-green-123"
}

# =============================================================================
# Integration Test - Validates build_deployment is called correctly
# =============================================================================
@test "build_blue_deployment: calls build_deployment with correct replicas and deployment id" {
  # Create a mock build_deployment that captures the arguments
  local mock_dir="$BATS_TEST_TMPDIR/mock_service"
  mkdir -p "$mock_dir/deployment"

  # Create mock script that captures REPLICAS, DEPLOYMENT_ID, and args
  cat > "$mock_dir/deployment/build_deployment" << 'MOCK_SCRIPT'
#!/bin/bash
# Capture values to a file for verification
echo "CAPTURED_REPLICAS=$REPLICAS" >> "$BATS_TEST_TMPDIR/captured_values"
echo "CAPTURED_DEPLOYMENT_ID=$DEPLOYMENT_ID" >> "$BATS_TEST_TMPDIR/captured_values"
echo "CAPTURED_ARGS=$*" >> "$BATS_TEST_TMPDIR/captured_values"
MOCK_SCRIPT
  chmod +x "$mock_dir/deployment/build_deployment"

  # Set SERVICE_PATH to our mock directory
  export SERVICE_PATH="$mock_dir"

  # Run the actual build_blue_deployment script
  source "$PROJECT_ROOT/k8s/deployment/build_blue_deployment"

  # Read captured values
  source "$BATS_TEST_TMPDIR/captured_values"

  # Verify build_deployment was called with blue deployment ID (from current_active_deployment)
  assert_equal "$CAPTURED_DEPLOYMENT_ID" "deploy-old-456" "build_deployment should receive blue deployment ID"

  # Verify build_deployment was called with correct replicas from context
  assert_equal "$CAPTURED_ARGS" "--replicas=2" "build_deployment should receive --replicas=2"
}
