#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/build_context - deployment configuration
# Tests focus on validate_status function and replica calculation logic
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Extract validate_status function from build_context for isolated testing
  eval "$(sed -n '/^validate_status()/,/^}/p' "$PROJECT_ROOT/k8s/deployment/build_context")"
}

teardown() {
  unset -f validate_status 2>/dev/null || true
}

# =============================================================================
# validate_status Function Tests - start-initial
# =============================================================================
@test "deployment/build_context: validate_status accepts creating for start-initial" {
  run validate_status "start-initial" "creating"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts waiting_for_instances for start-initial" {
  run validate_status "start-initial" "waiting_for_instances"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts running for start-initial" {
  run validate_status "start-initial" "running"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status rejects deleting for start-initial" {
  run validate_status "start-initial" "deleting"
  [ "$status" -ne 0 ]
}

@test "deployment/build_context: validate_status rejects failed for start-initial" {
  run validate_status "start-initial" "failed"
  [ "$status" -ne 0 ]
}

# =============================================================================
# validate_status Function Tests - start-blue-green
# =============================================================================
@test "deployment/build_context: validate_status accepts creating for start-blue-green" {
  run validate_status "start-blue-green" "creating"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts waiting_for_instances for start-blue-green" {
  run validate_status "start-blue-green" "waiting_for_instances"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts running for start-blue-green" {
  run validate_status "start-blue-green" "running"
  [ "$status" -eq 0 ]
}

# =============================================================================
# validate_status Function Tests - switch-traffic
# =============================================================================
@test "deployment/build_context: validate_status accepts running for switch-traffic" {
  run validate_status "switch-traffic" "running"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts waiting_for_instances for switch-traffic" {
  run validate_status "switch-traffic" "waiting_for_instances"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status rejects creating for switch-traffic" {
  run validate_status "switch-traffic" "creating"
  [ "$status" -ne 0 ]
}

# =============================================================================
# validate_status Function Tests - rollback-deployment
# =============================================================================
@test "deployment/build_context: validate_status accepts rolling_back for rollback-deployment" {
  run validate_status "rollback-deployment" "rolling_back"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts cancelling for rollback-deployment" {
  run validate_status "rollback-deployment" "cancelling"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status rejects running for rollback-deployment" {
  run validate_status "rollback-deployment" "running"
  [ "$status" -ne 0 ]
}

# =============================================================================
# validate_status Function Tests - finalize-blue-green
# =============================================================================
@test "deployment/build_context: validate_status accepts finalizing for finalize-blue-green" {
  run validate_status "finalize-blue-green" "finalizing"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts cancelling for finalize-blue-green" {
  run validate_status "finalize-blue-green" "cancelling"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status rejects running for finalize-blue-green" {
  run validate_status "finalize-blue-green" "running"
  [ "$status" -ne 0 ]
}

# =============================================================================
# validate_status Function Tests - delete-deployment
# =============================================================================
@test "deployment/build_context: validate_status accepts deleting for delete-deployment" {
  run validate_status "delete-deployment" "deleting"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts cancelling for delete-deployment" {
  run validate_status "delete-deployment" "cancelling"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts rolling_back for delete-deployment" {
  run validate_status "delete-deployment" "rolling_back"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status rejects running for delete-deployment" {
  run validate_status "delete-deployment" "running"
  [ "$status" -ne 0 ]
}

# =============================================================================
# validate_status Function Tests - Unknown Action
# =============================================================================
@test "deployment/build_context: validate_status accepts any status for unknown action" {
  run validate_status "custom-action" "any_status"
  [ "$status" -eq 0 ]
}

@test "deployment/build_context: validate_status accepts any status for empty action" {
  run validate_status "" "running"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Replica Calculation Tests (using bc)
# =============================================================================
@test "deployment/build_context: MIN_REPLICAS calculation rounds up" {
  # MIN_REPLICAS = ceil(REPLICAS / 10)
  REPLICAS=15
  MIN_REPLICAS=$(echo "scale=10; $REPLICAS / 10" | bc)
  MIN_REPLICAS=$(echo "$MIN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')

  # 15 / 10 = 1.5, should round up to 2
  assert_equal "$MIN_REPLICAS" "2"
}

@test "deployment/build_context: MIN_REPLICAS is 1 for 10 replicas" {
  REPLICAS=10
  MIN_REPLICAS=$(echo "scale=10; $REPLICAS / 10" | bc)
  MIN_REPLICAS=$(echo "$MIN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')

  assert_equal "$MIN_REPLICAS" "1"
}

@test "deployment/build_context: MIN_REPLICAS is 1 for 5 replicas" {
  REPLICAS=5
  MIN_REPLICAS=$(echo "scale=10; $REPLICAS / 10" | bc)
  MIN_REPLICAS=$(echo "$MIN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')

  # 5 / 10 = 0.5, should round up to 1
  assert_equal "$MIN_REPLICAS" "1"
}

@test "deployment/build_context: GREEN_REPLICAS calculation for 50% traffic" {
  REPLICAS=10
  SWITCH_TRAFFIC=50
  GREEN_REPLICAS=$(echo "scale=10; ($REPLICAS * $SWITCH_TRAFFIC) / 100" | bc)
  GREEN_REPLICAS=$(echo "$GREEN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')

  # 50% of 10 = 5
  assert_equal "$GREEN_REPLICAS" "5"
}

@test "deployment/build_context: GREEN_REPLICAS rounds up for fractional result" {
  REPLICAS=7
  SWITCH_TRAFFIC=30
  GREEN_REPLICAS=$(echo "scale=10; ($REPLICAS * $SWITCH_TRAFFIC) / 100" | bc)
  GREEN_REPLICAS=$(echo "$GREEN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')

  # 30% of 7 = 2.1, should round up to 3
  assert_equal "$GREEN_REPLICAS" "3"
}

@test "deployment/build_context: BLUE_REPLICAS is remainder" {
  REPLICAS=10
  GREEN_REPLICAS=6
  BLUE_REPLICAS=$(( REPLICAS - GREEN_REPLICAS ))

  assert_equal "$BLUE_REPLICAS" "4"
}

@test "deployment/build_context: BLUE_REPLICAS respects minimum" {
  REPLICAS=10
  GREEN_REPLICAS=10
  MIN_REPLICAS=1
  BLUE_REPLICAS=$(( REPLICAS - GREEN_REPLICAS ))
  BLUE_REPLICAS=$(( MIN_REPLICAS > BLUE_REPLICAS ? MIN_REPLICAS : BLUE_REPLICAS ))

  # Should be MIN_REPLICAS (1) since REPLICAS - GREEN = 0
  assert_equal "$BLUE_REPLICAS" "1"
}

@test "deployment/build_context: GREEN_REPLICAS respects minimum" {
  GREEN_REPLICAS=0
  MIN_REPLICAS=1
  GREEN_REPLICAS=$(( MIN_REPLICAS > GREEN_REPLICAS ? MIN_REPLICAS : GREEN_REPLICAS ))

  assert_equal "$GREEN_REPLICAS" "1"
}

# =============================================================================
# Service Account Name Generation Tests
# =============================================================================
@test "deployment/build_context: generates service account name when IAM enabled" {
  IAM='{"ENABLED":"true","PREFIX":"np-role"}'
  SCOPE_ID="scope-123"

  IAM_ENABLED=$(echo "$IAM" | jq -r .ENABLED)
  SERVICE_ACCOUNT_NAME=""

  if [[ "$IAM_ENABLED" == "true" ]]; then
    SERVICE_ACCOUNT_NAME=$(echo "$IAM" | jq -r .PREFIX)-"$SCOPE_ID"
  fi

  assert_equal "$SERVICE_ACCOUNT_NAME" "np-role-scope-123"
}

@test "deployment/build_context: service account name is empty when IAM disabled" {
  IAM='{"ENABLED":"false","PREFIX":"np-role"}'
  SCOPE_ID="scope-123"

  IAM_ENABLED=$(echo "$IAM" | jq -r .ENABLED)
  SERVICE_ACCOUNT_NAME=""

  if [[ "$IAM_ENABLED" == "true" ]]; then
    SERVICE_ACCOUNT_NAME=$(echo "$IAM" | jq -r .PREFIX)-"$SCOPE_ID"
  fi

  assert_empty "$SERVICE_ACCOUNT_NAME"
}

# =============================================================================
# Traffic Container Image Tests
# =============================================================================
@test "deployment/build_context: uses websocket version for web_sockets protocol" {
  SCOPE_TRAFFIC_PROTOCOL="web_sockets"
  TRAFFIC_CONTAINER_VERSION="latest"

  if [[ "$SCOPE_TRAFFIC_PROTOCOL" == "web_sockets" ]]; then
    TRAFFIC_CONTAINER_VERSION="websocket2"
  fi

  assert_equal "$TRAFFIC_CONTAINER_VERSION" "websocket2"
}

@test "deployment/build_context: uses latest version for http protocol" {
  SCOPE_TRAFFIC_PROTOCOL="http"
  TRAFFIC_CONTAINER_VERSION="latest"

  if [[ "$SCOPE_TRAFFIC_PROTOCOL" == "web_sockets" ]]; then
    TRAFFIC_CONTAINER_VERSION="websocket2"
  fi

  assert_equal "$TRAFFIC_CONTAINER_VERSION" "latest"
}

# =============================================================================
# Pod Disruption Budget Tests
# =============================================================================
@test "deployment/build_context: PDB defaults to disabled" {
  unset POD_DISRUPTION_BUDGET_ENABLED

  PDB_ENABLED=${POD_DISRUPTION_BUDGET_ENABLED:-"false"}

  assert_equal "$PDB_ENABLED" "false"
}

@test "deployment/build_context: PDB_MAX_UNAVAILABLE defaults to 25%" {
  unset POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE

  PDB_MAX_UNAVAILABLE=${POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE:-"25%"}

  assert_equal "$PDB_MAX_UNAVAILABLE" "25%"
}

@test "deployment/build_context: PDB respects custom enabled value" {
  POD_DISRUPTION_BUDGET_ENABLED="true"

  PDB_ENABLED=${POD_DISRUPTION_BUDGET_ENABLED:-"false"}

  assert_equal "$PDB_ENABLED" "true"
}

@test "deployment/build_context: PDB respects custom max_unavailable value" {
  POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE="50%"

  PDB_MAX_UNAVAILABLE=${POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE:-"25%"}

  assert_equal "$PDB_MAX_UNAVAILABLE" "50%"
}

# =============================================================================
# Image Pull Secrets Tests
# =============================================================================
@test "deployment/build_context: uses PULL_SECRETS when set" {
  PULL_SECRETS='["secret1"]'
  IMAGE_PULL_SECRETS="{}"

  if [[ -n "$PULL_SECRETS" ]]; then
    IMAGE_PULL_SECRETS=$PULL_SECRETS
  fi

  assert_equal "$IMAGE_PULL_SECRETS" '["secret1"]'
}

@test "deployment/build_context: falls back to IMAGE_PULL_SECRETS" {
  PULL_SECRETS=""
  IMAGE_PULL_SECRETS='{"ENABLED":true}'

  if [[ -n "$PULL_SECRETS" ]]; then
    IMAGE_PULL_SECRETS=$PULL_SECRETS
  fi

  assert_contains "$IMAGE_PULL_SECRETS" "ENABLED"
}

# =============================================================================
# Logging Format Tests
# =============================================================================
@test "deployment/build_context: validate_status outputs action message with 📝 emoji" {
  run validate_status "start-initial" "creating"

  assert_contains "$output" "📝 Running action 'start-initial' (current status: 'creating', expected: creating, waiting_for_instances or running)"
}


@test "deployment/build_context: validate_status accepts any status message for unknown action" {
  run validate_status "custom-action" "any_status"

  assert_contains "$output" "📝 Running action 'custom-action', any deployment status is accepted"
}

@test "deployment/build_context: invalid status error includes possible causes and how to fix" {
  # Create a test script that sources build_context with invalid status
  local test_script="$BATS_TEST_TMPDIR/test_invalid_status.sh"

  cat > "$test_script" << 'SCRIPT'
#!/bin/bash
export SERVICE_PATH="$1"
export SERVICE_ACTION="start-initial"
export CONTEXT='{"deployment":{"status":"failed"}}'

# Mock scope/build_context to avoid dependencies
mkdir -p "$SERVICE_PATH/scope"
echo "# no-op" > "$SERVICE_PATH/scope/build_context"

source "$SERVICE_PATH/deployment/build_context"
SCRIPT
  chmod +x "$test_script"

  # Create mock service path
  local mock_service="$BATS_TEST_TMPDIR/mock_k8s"
  mkdir -p "$mock_service/deployment"
  cp "$PROJECT_ROOT/k8s/deployment/build_context" "$mock_service/deployment/"

  run "$test_script" "$mock_service"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Invalid deployment status 'failed' for action 'start-initial'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Deployment status changed during workflow execution"
  assert_contains "$output" "Another action is already running on this deployment"
  assert_contains "$output" "Deployment was modified externally"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Wait for any in-progress actions to complete"
  assert_contains "$output" "Check the deployment status in the nullplatform dashboard"
  assert_contains "$output" "Retry the action once the deployment is in the expected state"
}

@test "deployment/build_context: ConfigMap not found error includes troubleshooting info" {
  # Create a test script that triggers ConfigMap validation error
  local test_script="$BATS_TEST_TMPDIR/test_configmap_error.sh"

  cat > "$test_script" << 'SCRIPT'
#!/bin/bash
export SERVICE_PATH="$1"
export SERVICE_ACTION="start-initial"
export TRAFFIC_MANAGER_CONFIG_MAP="test-config"
export K8S_NAMESPACE="test-ns"
export CONTEXT='{
  "deployment":{"status":"creating","id":"deploy-123"},
  "scope":{"capabilities":{"scaling_type":"fixed","fixed_instances":1}}
}'

# Mock scope/build_context
mkdir -p "$SERVICE_PATH/scope"
echo "# no-op" > "$SERVICE_PATH/scope/build_context"

# Mock kubectl to simulate ConfigMap not found
kubectl() {
  return 1
}
export -f kubectl

source "$SERVICE_PATH/deployment/build_context"
SCRIPT
  chmod +x "$test_script"

  # Create mock service path
  local mock_service="$BATS_TEST_TMPDIR/mock_k8s"
  mkdir -p "$mock_service/deployment"
  cp "$PROJECT_ROOT/k8s/deployment/build_context" "$mock_service/deployment/"

  run "$test_script" "$mock_service"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ ConfigMap 'test-config' does not exist in namespace 'test-ns'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "ConfigMap was not created before deployment"
  assert_contains "$output" "ConfigMap name is misspelled in values.yaml"
  assert_contains "$output" "ConfigMap was deleted or exists in a different namespace"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Create the ConfigMap: kubectl create configmap test-config -n test-ns --from-file=nginx.conf --from-file=default.conf"
  assert_contains "$output" "Verify the ConfigMap name in your scope configuration"
}
