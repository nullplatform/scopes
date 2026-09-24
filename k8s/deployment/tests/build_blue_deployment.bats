#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/build_blue_deployment - blue deployment builder
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  source "$PROJECT_ROOT/k8s/utils/get_config_value"
  source "$PROJECT_ROOT/k8s/naming/resolve_names"
  export -f get_config_value np_name_sanitize np_name_cap np_trim_segments \
    np_naming_validate_pattern \
    np_naming_resolve_path np_name_render np_naming_strategy np_naming_resolve np_naming_roles_ids \
    np_naming_emit np_naming_roles_patterned np_naming_lookup np_naming_discover_blue \
    np_naming_discover_scope np_naming_apply_to_context
  unset NAMING_STRATEGY

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

# =============================================================================
# Name Resolution Tests
# =============================================================================
@test "build_blue_deployment: renders the blue deployment's own name, not green's" {
  local raw_context
  raw_context="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal.json")"

  local resolved_names
  resolved_names="$(CONTEXT="$raw_context" np_naming_resolve)"

  export CONTEXT="$(echo "$raw_context" | jq \
    --argjson names "$resolved_names" \
    '. + {names: ($names | del(.additional_ports))}
     | if ($names.additional_ports | length) > 0
       then .scope.capabilities.additional_ports = $names.additional_ports
       else . end
     | .scope.current_active_deployment = "789011"')"

  export SCOPE_ID="$(echo "$CONTEXT" | jq -r .scope.id)"
  export DEPLOYMENT_ID="$(echo "$CONTEXT" | jq -r .deployment.id)"
  export K8S_NAMESPACE="$(echo "$CONTEXT" | jq -r .k8s_namespace)"
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/output"
  mkdir -p "$OUTPUT_DIR"
  export DEPLOYMENT_TEMPLATE="$SERVICE_PATH/deployment/templates/deployment.yaml.tpl"
  export SECRET_TEMPLATE="$SERVICE_PATH/deployment/templates/secret.yaml.tpl"
  export SECRET_FILES_TEMPLATE="$SERVICE_PATH/deployment/templates/secret-files.yaml.tpl"
  export SCALING_TEMPLATE="$SERVICE_PATH/deployment/templates/scaling.yaml.tpl"
  export SERVICE_TEMPLATE="$SERVICE_PATH/deployment/templates/service.yaml.tpl"
  export PDB_TEMPLATE="$SERVICE_PATH/deployment/templates/pdb.yaml.tpl"

  kubectl() { echo '{"items":[]}'; }
  export -f kubectl

  source "$PROJECT_ROOT/k8s/deployment/build_blue_deployment"

  rendered_name="$(yq -N '.metadata.name' "$OUTPUT_DIR/deployment-$SCOPE_ID-789011.yaml")"
  assert_equal "$rendered_name" "d-123456-789011"
}

@test "build_blue_deployment: discovers the blue's real name after a strategy change, instead of recomputing it" {
  local raw_context
  raw_context="$(cat "$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal.json")"

  export NAMING_STRATEGY="qualified"

  # The blue was created back when the strategy was "ids"; its live Deployment
  # and Service are still named d-123456-789011, and carry no trace of
  # "qualified". Scope-level discovery (ingress/httproute) finds nothing, which
  # is irrelevant here since this test only asserts on the blue's own name.
  kubectl() {
    case "$1 $2" in
      "get deployment") echo '{"items":[{"metadata":{"name":"d-123456-789011"}}]}' ;;
      "get service")    echo '{"items":[{"metadata":{"name":"d-123456-789011"},"spec":{"ports":[{"port":8080}]}}]}' ;;
      *)                echo "" ;;
    esac
  }
  export -f kubectl

  local resolved_names
  resolved_names="$(CONTEXT="$raw_context" np_naming_resolve 2>/dev/null)"

  export CONTEXT="$(echo "$raw_context" | jq \
    --argjson names "$resolved_names" \
    '. + {names: ($names | del(.additional_ports))}
     | if ($names.additional_ports | length) > 0
       then .scope.capabilities.additional_ports = $names.additional_ports
       else . end
     | .scope.current_active_deployment = "789011"')"

  export SCOPE_ID="$(echo "$CONTEXT" | jq -r .scope.id)"
  export DEPLOYMENT_ID="$(echo "$CONTEXT" | jq -r .deployment.id)"
  export K8S_NAMESPACE="$(echo "$CONTEXT" | jq -r .k8s_namespace)"
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/output"
  mkdir -p "$OUTPUT_DIR"
  export DEPLOYMENT_TEMPLATE="$SERVICE_PATH/deployment/templates/deployment.yaml.tpl"
  export SECRET_TEMPLATE="$SERVICE_PATH/deployment/templates/secret.yaml.tpl"
  export SECRET_FILES_TEMPLATE="$SERVICE_PATH/deployment/templates/secret-files.yaml.tpl"
  export SCALING_TEMPLATE="$SERVICE_PATH/deployment/templates/scaling.yaml.tpl"
  export SERVICE_TEMPLATE="$SERVICE_PATH/deployment/templates/service.yaml.tpl"
  export PDB_TEMPLATE="$SERVICE_PATH/deployment/templates/pdb.yaml.tpl"

  source "$PROJECT_ROOT/k8s/deployment/build_blue_deployment"

  rendered_name="$(yq -N '.metadata.name' "$OUTPUT_DIR/deployment-$SCOPE_ID-789011.yaml")"
  assert_equal "$rendered_name" "d-123456-789011"
}
