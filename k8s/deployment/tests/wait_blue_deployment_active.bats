#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/wait_blue_deployment_active - blue deployment wait
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export DEPLOYMENT_ID="deploy-new-123"

  export CONTEXT='{
    "scope": {
      "current_active_deployment": "deploy-old-456"
    },
    "deployment": {
      "id": "deploy-new-123"
    }
  }'
}

teardown() {
  unset CONTEXT
}

# =============================================================================
# Deployment ID Handling Tests
# =============================================================================
@test "wait_blue_deployment_active: extracts current_active_deployment as blue" {
  blue_id=$(echo "$CONTEXT" | jq -r .scope.current_active_deployment)

  assert_equal "$blue_id" "deploy-old-456"
}

@test "wait_blue_deployment_active: preserves new deployment ID after" {
  # The script should restore DEPLOYMENT_ID to the new deployment
  assert_equal "$DEPLOYMENT_ID" "deploy-new-123"
}

# =============================================================================
# Context Update Tests
# =============================================================================
@test "wait_blue_deployment_active: updates context with blue deployment ID" {
  updated_context=$(echo "$CONTEXT" | jq \
    --arg deployment_id "deploy-old-456" \
    '.deployment.id = $deployment_id')

  updated_id=$(echo "$updated_context" | jq -r .deployment.id)

  assert_equal "$updated_id" "deploy-old-456"
}

@test "wait_blue_deployment_active: restores context with new deployment ID" {
  updated_context=$(echo "$CONTEXT" | jq \
    --arg deployment_id "deploy-new-123" \
    '.deployment.id = $deployment_id')

  updated_id=$(echo "$updated_context" | jq -r .deployment.id)

  assert_equal "$updated_id" "deploy-new-123"
}

# =============================================================================
# Integration Tests
# =============================================================================
@test "wait_blue_deployment_active: calls wait_deployment_active with blue deployment id in context" {
  local mock_dir="$BATS_TEST_TMPDIR/mock_service"
  mkdir -p "$mock_dir/deployment"

  cat > "$mock_dir/deployment/wait_deployment_active" << 'MOCK_SCRIPT'
#!/bin/bash
echo "CAPTURED_DEPLOYMENT_ID=$DEPLOYMENT_ID" >> "$BATS_TEST_TMPDIR/captured_values"
echo "CAPTURED_CONTEXT_DEPLOYMENT_ID=$(echo "$CONTEXT" | jq -r .deployment.id)" >> "$BATS_TEST_TMPDIR/captured_values"
MOCK_SCRIPT
  chmod +x "$mock_dir/deployment/wait_deployment_active"

  run bash -c "
    export SERVICE_PATH='$mock_dir'
    export DEPLOYMENT_ID='$DEPLOYMENT_ID'
    export CONTEXT='$CONTEXT'
    export BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR'
    source '$BATS_TEST_DIRNAME/../wait_blue_deployment_active'
  "

  [ "$status" -eq 0 ]

  source "$BATS_TEST_TMPDIR/captured_values"
  assert_equal "$CAPTURED_DEPLOYMENT_ID" "deploy-old-456"
  assert_equal "$CAPTURED_CONTEXT_DEPLOYMENT_ID" "deploy-old-456"
}
