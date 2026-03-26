#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/build_context
# Tests validate_status function, replica calculation, and get_config_value usage
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$PROJECT_ROOT/k8s/utils/get_config_value"

  # Base CONTEXT for tests
  export CONTEXT='{
    "deployment": {"status": "creating", "id": "deploy-123"},
    "scope": {"id": "scope-456", "capabilities": {"scaling_type": "fixed", "fixed_instances": 2}}
  }'

  # Extract validate_status function from build_context for isolated testing
  eval "$(sed -n '/^validate_status()/,/^}/p' "$PROJECT_ROOT/k8s/deployment/build_context")"
}

teardown() {
  unset -f validate_status 2>/dev/null || true
  unset CONTEXT DEPLOY_STRATEGY POD_DISRUPTION_BUDGET_ENABLED POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE 2>/dev/null || true
  unset TRAFFIC_CONTAINER_IMAGE TRAFFIC_MANAGER_CONFIG_MAP IMAGE_PULL_SECRETS IAM 2>/dev/null || true
}

# =============================================================================
# validate_status Function Tests
# =============================================================================
@test "validate_status: accepts valid statuses for start-initial and start-blue-green" {
  run validate_status "start-initial" "creating"
  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Running action 'start-initial' (current status: 'creating', expected: creating, waiting_for_instances or running)"

  run validate_status "start-initial" "waiting_for_instances"
  [ "$status" -eq 0 ]

  run validate_status "start-initial" "running"
  [ "$status" -eq 0 ]

  run validate_status "start-blue-green" "creating"
  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Running action 'start-blue-green' (current status: 'creating', expected: creating, waiting_for_instances or running)"
}

@test "validate_status: rejects invalid statuses for start-initial" {
  run validate_status "start-initial" "deleting"
  [ "$status" -ne 0 ]

  run validate_status "start-initial" "failed"
  [ "$status" -ne 0 ]
}

@test "validate_status: accepts valid statuses for switch-traffic" {
  run validate_status "switch-traffic" "running"
  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Running action 'switch-traffic' (current status: 'running', expected: running or waiting_for_instances)"

  run validate_status "switch-traffic" "waiting_for_instances"
  [ "$status" -eq 0 ]
}

@test "validate_status: rejects invalid statuses for switch-traffic" {
  run validate_status "switch-traffic" "creating"
  [ "$status" -ne 0 ]
}

@test "validate_status: accepts valid statuses for rollback-deployment" {
  run validate_status "rollback-deployment" "rolling_back"
  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Running action 'rollback-deployment' (current status: 'rolling_back', expected: rolling_back or cancelling)"

  run validate_status "rollback-deployment" "cancelling"
  [ "$status" -eq 0 ]
}

@test "validate_status: rejects invalid statuses for rollback-deployment" {
  run validate_status "rollback-deployment" "running"
  [ "$status" -ne 0 ]
}

@test "validate_status: accepts valid statuses for finalize-blue-green" {
  run validate_status "finalize-blue-green" "finalizing"
  [ "$status" -eq 0 ]

  run validate_status "finalize-blue-green" "cancelling"
  [ "$status" -eq 0 ]
}

@test "validate_status: rejects invalid statuses for finalize-blue-green" {
  run validate_status "finalize-blue-green" "running"
  [ "$status" -ne 0 ]
}

@test "validate_status: accepts valid statuses for delete-deployment" {
  run validate_status "delete-deployment" "deleting"
  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Running action 'delete-deployment' (current status: 'deleting', expected: deleting, rolling_back or cancelling)"

  run validate_status "delete-deployment" "cancelling"
  [ "$status" -eq 0 ]

  run validate_status "delete-deployment" "rolling_back"
  [ "$status" -eq 0 ]
}

@test "validate_status: rejects invalid statuses for delete-deployment" {
  run validate_status "delete-deployment" "running"
  [ "$status" -ne 0 ]
}

@test "validate_status: accepts any status for unknown or empty action" {
  run validate_status "custom-action" "any_status"
  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Running action 'custom-action', any deployment status is accepted"

  run validate_status "" "running"
  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Running action '', any deployment status is accepted"
}

# =============================================================================
# Replica Calculation Tests
# =============================================================================
@test "replica calculation: MIN_REPLICAS rounds up correctly" {
  # MIN_REPLICAS = ceil(REPLICAS / 10)

  # 15 / 10 = 1.5 -> rounds up to 2
  REPLICAS=15
  MIN_REPLICAS=$(echo "scale=10; $REPLICAS / 10" | bc)
  MIN_REPLICAS=$(echo "$MIN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')
  assert_equal "$MIN_REPLICAS" "2"

  # 10 / 10 = 1.0 -> stays 1
  REPLICAS=10
  MIN_REPLICAS=$(echo "scale=10; $REPLICAS / 10" | bc)
  MIN_REPLICAS=$(echo "$MIN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')
  assert_equal "$MIN_REPLICAS" "1"

  # 5 / 10 = 0.5 -> rounds up to 1
  REPLICAS=5
  MIN_REPLICAS=$(echo "scale=10; $REPLICAS / 10" | bc)
  MIN_REPLICAS=$(echo "$MIN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')
  assert_equal "$MIN_REPLICAS" "1"
}

@test "replica calculation: GREEN_REPLICAS calculates traffic percentage correctly" {
  # 50% of 10 = 5
  REPLICAS=10
  SWITCH_TRAFFIC=50
  GREEN_REPLICAS=$(echo "scale=10; ($REPLICAS * $SWITCH_TRAFFIC) / 100" | bc)
  GREEN_REPLICAS=$(echo "$GREEN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')
  assert_equal "$GREEN_REPLICAS" "5"

  # 30% of 7 = 2.1 -> rounds up to 3
  REPLICAS=7
  SWITCH_TRAFFIC=30
  GREEN_REPLICAS=$(echo "scale=10; ($REPLICAS * $SWITCH_TRAFFIC) / 100" | bc)
  GREEN_REPLICAS=$(echo "$GREEN_REPLICAS" | awk '{printf "%d", ($1 == int($1) ? $1 : int($1)+1)}')
  assert_equal "$GREEN_REPLICAS" "3"
}

@test "replica calculation: BLUE_REPLICAS respects minimum" {
  REPLICAS=10
  GREEN_REPLICAS=10
  MIN_REPLICAS=1
  BLUE_REPLICAS=$(( REPLICAS - GREEN_REPLICAS ))
  BLUE_REPLICAS=$(( MIN_REPLICAS > BLUE_REPLICAS ? MIN_REPLICAS : BLUE_REPLICAS ))
  assert_equal "$BLUE_REPLICAS" "1"

  # When remainder is larger than minimum, use remainder
  GREEN_REPLICAS=6
  BLUE_REPLICAS=$(( REPLICAS - GREEN_REPLICAS ))
  BLUE_REPLICAS=$(( MIN_REPLICAS > BLUE_REPLICAS ? MIN_REPLICAS : BLUE_REPLICAS ))
  assert_equal "$BLUE_REPLICAS" "4"
}

@test "replica calculation: GREEN_REPLICAS respects minimum" {
  GREEN_REPLICAS=0
  MIN_REPLICAS=1
  GREEN_REPLICAS=$(( MIN_REPLICAS > GREEN_REPLICAS ? MIN_REPLICAS : GREEN_REPLICAS ))
  assert_equal "$GREEN_REPLICAS" "1"
}

# =============================================================================
# Service Account Name Generation Tests
# =============================================================================
@test "service account: generates name when IAM enabled, empty when disabled" {
  SCOPE_ID="scope-123"

  # IAM enabled
  IAM='{"ENABLED":"true","PREFIX":"np-role"}'
  IAM_ENABLED=$(echo "$IAM" | jq -r .ENABLED)
  SERVICE_ACCOUNT_NAME=""
  if [[ "$IAM_ENABLED" == "true" ]]; then
    SERVICE_ACCOUNT_NAME=$(echo "$IAM" | jq -r .PREFIX)-"$SCOPE_ID"
  fi
  assert_equal "$SERVICE_ACCOUNT_NAME" "np-role-scope-123"

  # IAM disabled
  IAM='{"ENABLED":"false","PREFIX":"np-role"}'
  IAM_ENABLED=$(echo "$IAM" | jq -r .ENABLED)
  SERVICE_ACCOUNT_NAME=""
  if [[ "$IAM_ENABLED" == "true" ]]; then
    SERVICE_ACCOUNT_NAME=$(echo "$IAM" | jq -r .PREFIX)-"$SCOPE_ID"
  fi
  assert_empty "$SERVICE_ACCOUNT_NAME"
}

# =============================================================================
# Traffic Container Image Version Tests
# =============================================================================
@test "traffic container: uses websocket2 for web_sockets, latest for http" {
  # web_sockets protocol
  SCOPE_TRAFFIC_PROTOCOL="web_sockets"
  TRAFFIC_CONTAINER_VERSION="latest"
  if [[ "$SCOPE_TRAFFIC_PROTOCOL" == "web_sockets" ]]; then
    TRAFFIC_CONTAINER_VERSION="websocket2"
  fi
  assert_equal "$TRAFFIC_CONTAINER_VERSION" "websocket2"

  # http protocol
  SCOPE_TRAFFIC_PROTOCOL="http"
  TRAFFIC_CONTAINER_VERSION="latest"
  if [[ "$SCOPE_TRAFFIC_PROTOCOL" == "web_sockets" ]]; then
    TRAFFIC_CONTAINER_VERSION="websocket2"
  fi
  assert_equal "$TRAFFIC_CONTAINER_VERSION" "latest"
}

# =============================================================================
# Image Pull Secrets Tests
# =============================================================================
@test "image pull secrets: PULL_SECRETS takes precedence over IMAGE_PULL_SECRETS" {
  PULL_SECRETS='["secret1"]'
  IMAGE_PULL_SECRETS="{}"

  if [[ -n "$PULL_SECRETS" ]]; then
    IMAGE_PULL_SECRETS=$PULL_SECRETS
  fi

  assert_equal "$IMAGE_PULL_SECRETS" '["secret1"]'
}

# =============================================================================
# get_config_value Tests - DEPLOY_STRATEGY
# =============================================================================
@test "get_config_value: DEPLOY_STRATEGY priority - provider > env > default" {
  # Default when nothing set
  unset DEPLOY_STRATEGY
  result=$(get_config_value \
    --env DEPLOY_STRATEGY \
    --provider '.providers["scope-configurations"].deployment.deployment_strategy' \
    --default "blue-green"
  )
  assert_equal "$result" "blue-green"

  # Env var when no provider
  export DEPLOY_STRATEGY="rolling"
  result=$(get_config_value \
    --env DEPLOY_STRATEGY \
    --provider '.providers["scope-configurations"].deployment.deployment_strategy' \
    --default "blue-green"
  )
  assert_equal "$result" "rolling"

  # Provider wins over env var
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {"deployment": {"deployment_strategy": "canary"}}')
  result=$(get_config_value \
    --env DEPLOY_STRATEGY \
    --provider '.providers["scope-configurations"].deployment.deployment_strategy' \
    --default "blue-green"
  )
  assert_equal "$result" "canary"
}

# =============================================================================
# get_config_value Tests - PDB Configuration
# =============================================================================
@test "get_config_value: PDB_ENABLED priority - provider > env > default" {
  # Default
  unset POD_DISRUPTION_BUDGET_ENABLED
  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_ENABLED \
    --provider '.providers["scope-configurations"].deployment.pod_disruption_budget_enabled' \
    --default "false"
  )
  assert_equal "$result" "false"

  # Env var
  export POD_DISRUPTION_BUDGET_ENABLED="true"
  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_ENABLED \
    --provider '.providers["scope-configurations"].deployment.pod_disruption_budget_enabled' \
    --default "false"
  )
  assert_equal "$result" "true"

  # Provider wins
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {"deployment": {"pod_disruption_budget_enabled": "false"}}')
  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_ENABLED \
    --provider '.providers["scope-configurations"].deployment.pod_disruption_budget_enabled' \
    --default "false"
  )
  assert_equal "$result" "false"
}

@test "get_config_value: PDB_MAX_UNAVAILABLE priority - provider > env > default" {
  # Default
  unset POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE
  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE \
    --provider '.providers["scope-configurations"].deployment.pod_disruption_budget_max_unavailable' \
    --default "25%"
  )
  assert_equal "$result" "25%"

  # Env var
  export POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE="2"
  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE \
    --provider '.providers["scope-configurations"].deployment.pod_disruption_budget_max_unavailable' \
    --default "25%"
  )
  assert_equal "$result" "2"

  # Provider wins
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {"deployment": {"pod_disruption_budget_max_unavailable": "75%"}}')
  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE \
    --provider '.providers["scope-configurations"].deployment.pod_disruption_budget_max_unavailable' \
    --default "25%"
  )
  assert_equal "$result" "75%"
}

# =============================================================================
# get_config_value Tests - TRAFFIC_CONTAINER_IMAGE
# =============================================================================
@test "get_config_value: TRAFFIC_CONTAINER_IMAGE priority - provider > env > default" {
  # Default
  unset TRAFFIC_CONTAINER_IMAGE
  result=$(get_config_value \
    --env TRAFFIC_CONTAINER_IMAGE \
    --provider '.providers["scope-configurations"].deployment.traffic_container_image' \
    --default "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
  )
  assert_equal "$result" "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"

  # Env var
  export TRAFFIC_CONTAINER_IMAGE="env.ecr.aws/traffic:custom"
  result=$(get_config_value \
    --env TRAFFIC_CONTAINER_IMAGE \
    --provider '.providers["scope-configurations"].deployment.traffic_container_image' \
    --default "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
  )
  assert_equal "$result" "env.ecr.aws/traffic:custom"

  # Provider wins
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {"deployment": {"traffic_container_image": "provider.ecr.aws/traffic:v3.0"}}')
  result=$(get_config_value \
    --env TRAFFIC_CONTAINER_IMAGE \
    --provider '.providers["scope-configurations"].deployment.traffic_container_image' \
    --default "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
  )
  assert_equal "$result" "provider.ecr.aws/traffic:v3.0"
}

# =============================================================================
# get_config_value Tests - TRAFFIC_MANAGER_CONFIG_MAP
# =============================================================================
@test "get_config_value: TRAFFIC_MANAGER_CONFIG_MAP priority - provider > env > default" {
  # Default (empty)
  unset TRAFFIC_MANAGER_CONFIG_MAP
  result=$(get_config_value \
    --env TRAFFIC_MANAGER_CONFIG_MAP \
    --provider '.providers["scope-configurations"].deployment.traffic_manager_config_map' \
    --default ""
  )
  assert_empty "$result"

  # Env var
  export TRAFFIC_MANAGER_CONFIG_MAP="env-traffic-config"
  result=$(get_config_value \
    --env TRAFFIC_MANAGER_CONFIG_MAP \
    --provider '.providers["scope-configurations"].deployment.traffic_manager_config_map' \
    --default ""
  )
  assert_equal "$result" "env-traffic-config"

  # Provider wins
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {"deployment": {"traffic_manager_config_map": "provider-traffic-config"}}')
  result=$(get_config_value \
    --env TRAFFIC_MANAGER_CONFIG_MAP \
    --provider '.providers["scope-configurations"].deployment.traffic_manager_config_map' \
    --default ""
  )
  assert_equal "$result" "provider-traffic-config"
}

# =============================================================================
# get_config_value Tests - IMAGE_PULL_SECRETS
# =============================================================================
@test "get_config_value: IMAGE_PULL_SECRETS reads from provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "security": {
      "image_pull_secrets_enabled": true,
      "image_pull_secrets": ["custom-secret", "ecr-secret"]
    }
  }')

  enabled=$(get_config_value \
    --provider '.providers["scope-configurations"].security.image_pull_secrets_enabled' \
    --default "false"
  )
  secrets=$(get_config_value \
    --provider '.providers["scope-configurations"].security.image_pull_secrets | @json' \
    --default "[]"
  )

  assert_equal "$enabled" "true"
  assert_contains "$secrets" "custom-secret"
  assert_contains "$secrets" "ecr-secret"
}

# =============================================================================
# get_config_value Tests - IAM Configuration
# =============================================================================
@test "get_config_value: IAM reads from provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "security": {
      "iam_enabled": true,
      "iam_prefix": "custom-prefix",
      "iam_policies": ["arn:aws:iam::123:policy/test"],
      "iam_boundary_arn": "arn:aws:iam::123:policy/boundary"
    }
  }')

  enabled=$(get_config_value \
    --provider '.providers["scope-configurations"].security.iam_enabled' \
    --default "false"
  )
  prefix=$(get_config_value \
    --provider '.providers["scope-configurations"].security.iam_prefix' \
    --default ""
  )
  policies=$(get_config_value \
    --provider '.providers["scope-configurations"].security.iam_policies | @json' \
    --default "[]"
  )
  boundary=$(get_config_value \
    --provider '.providers["scope-configurations"].security.iam_boundary_arn' \
    --default ""
  )

  assert_equal "$enabled" "true"
  assert_equal "$prefix" "custom-prefix"
  assert_contains "$policies" "arn:aws:iam::123:policy/test"
  assert_equal "$boundary" "arn:aws:iam::123:policy/boundary"
}

@test "get_config_value: IAM uses defaults when not configured" {
  enabled=$(get_config_value \
    --provider '.providers["scope-configurations"].security.iam_enabled' \
    --default "false"
  )
  prefix=$(get_config_value \
    --provider '.providers["scope-configurations"].security.iam_prefix' \
    --default ""
  )

  assert_equal "$enabled" "false"
  assert_empty "$prefix"
}

# =============================================================================
# get_config_value Tests - Complete Configuration Hierarchy
# =============================================================================
@test "get_config_value: complete deployment configuration from provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "deployment": {
      "traffic_container_image": "custom.ecr.aws/traffic:v1",
      "pod_disruption_budget_enabled": "true",
      "pod_disruption_budget_max_unavailable": "1",
      "traffic_manager_config_map": "my-config-map",
      "deployment_strategy": "rolling"
    }
  }')

  unset TRAFFIC_CONTAINER_IMAGE POD_DISRUPTION_BUDGET_ENABLED POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE
  unset TRAFFIC_MANAGER_CONFIG_MAP DEPLOY_STRATEGY

  traffic_image=$(get_config_value \
    --env TRAFFIC_CONTAINER_IMAGE \
    --provider '.providers["scope-configurations"].deployment.traffic_container_image' \
    --default "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
  )
  assert_equal "$traffic_image" "custom.ecr.aws/traffic:v1"

  pdb_enabled=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_ENABLED \
    --provider '.providers["scope-configurations"].deployment.pod_disruption_budget_enabled' \
    --default "false"
  )
  assert_equal "$pdb_enabled" "true"

  pdb_max=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE \
    --provider '.providers["scope-configurations"].deployment.pod_disruption_budget_max_unavailable' \
    --default "25%"
  )
  assert_equal "$pdb_max" "1"

  config_map=$(get_config_value \
    --env TRAFFIC_MANAGER_CONFIG_MAP \
    --provider '.providers["scope-configurations"].deployment.traffic_manager_config_map' \
    --default ""
  )
  assert_equal "$config_map" "my-config-map"

  strategy=$(get_config_value \
    --env DEPLOY_STRATEGY \
    --provider '.providers["scope-configurations"].deployment.deployment_strategy' \
    --default "blue-green"
  )
  assert_equal "$strategy" "rolling"
}

# =============================================================================
# Error Handling Tests
# =============================================================================
@test "error: invalid deployment status shows full troubleshooting info" {
  local test_script="$BATS_TEST_TMPDIR/test_invalid_status.sh"

  cat > "$test_script" << 'SCRIPT'
#!/bin/bash
export SERVICE_PATH="$1"
export SERVICE_ACTION="start-initial"
export CONTEXT='{"deployment":{"status":"failed"}}'

# Mock scope/build_context that sources get_config_value
mkdir -p "$SERVICE_PATH/scope"
cat > "$SERVICE_PATH/scope/build_context" << 'MOCK_SCOPE'
source "$SERVICE_PATH/utils/get_config_value"
MOCK_SCOPE

source "$SERVICE_PATH/deployment/build_context"
SCRIPT
  chmod +x "$test_script"

  local mock_service="$BATS_TEST_TMPDIR/mock_k8s"
  mkdir -p "$mock_service/deployment" "$mock_service/utils"
  cp "$PROJECT_ROOT/k8s/deployment/build_context" "$mock_service/deployment/"
  cp "$PROJECT_ROOT/k8s/utils/get_config_value" "$mock_service/utils/"

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

@test "error: ConfigMap not found shows full troubleshooting info" {
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

# Mock scope/build_context that sources get_config_value
mkdir -p "$SERVICE_PATH/scope"
cat > "$SERVICE_PATH/scope/build_context" << 'MOCK_SCOPE'
source "$SERVICE_PATH/utils/get_config_value"
MOCK_SCOPE

kubectl() {
  return 1
}
export -f kubectl

source "$SERVICE_PATH/deployment/build_context"
SCRIPT
  chmod +x "$test_script"

  local mock_service="$BATS_TEST_TMPDIR/mock_k8s"
  mkdir -p "$mock_service/deployment" "$mock_service/utils"
  cp "$PROJECT_ROOT/k8s/deployment/build_context" "$mock_service/deployment/"
  cp "$PROJECT_ROOT/k8s/utils/get_config_value" "$mock_service/utils/"

  run "$test_script" "$mock_service"

  [ "$status" -ne 0 ]
  assert_contains "$output" "🔍 Validating ConfigMap 'test-config' in namespace 'test-ns'"
  assert_contains "$output" "❌ ConfigMap 'test-config' does not exist in namespace 'test-ns'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "ConfigMap was not created before deployment"
  assert_contains "$output" "ConfigMap name is misspelled in values.yaml"
  assert_contains "$output" "ConfigMap was deleted or exists in a different namespace"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Create the ConfigMap: kubectl create configmap test-config -n test-ns --from-file=nginx.conf --from-file=default.conf"
  assert_contains "$output" "Verify the ConfigMap name in your scope configuration"
}
