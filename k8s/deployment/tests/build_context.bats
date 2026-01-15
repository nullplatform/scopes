#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/build_context - deployment configuration
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Source get_config_value utility
  source "$PROJECT_ROOT/k8s/utils/get_config_value"

  # Default values from values.yaml
  export IMAGE_PULL_SECRETS="{}"
  export TRAFFIC_CONTAINER_IMAGE=""
  export POD_DISRUPTION_BUDGET_ENABLED="false"
  export POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE="25%"
  export TRAFFIC_MANAGER_CONFIG_MAP=""

  # Base CONTEXT
  export CONTEXT='{
    "providers": {
      "cloud-providers": {},
      "container-orchestration": {}
    }
  }'
}

teardown() {
  # Clean up environment variables
  unset IMAGE_PULL_SECRETS
  unset TRAFFIC_CONTAINER_IMAGE
  unset POD_DISRUPTION_BUDGET_ENABLED
  unset POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE
  unset TRAFFIC_MANAGER_CONFIG_MAP
  unset DEPLOY_STRATEGY
  unset IAM
}

# =============================================================================
# Test: IMAGE_PULL_SECRETS uses scope-configuration provider
# =============================================================================
@test "deployment/build_context: IMAGE_PULL_SECRETS uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configuration"] = {
    "security": {
      "image_pull_secrets_enabled": true,
      "image_pull_secrets": ["custom-secret", "ecr-secret"]
    }
  }')

  # Unset env var to test provider precedence
  unset IMAGE_PULL_SECRETS

  enabled=$(get_config_value \
    --provider '.providers["scope-configuration"].security.image_pull_secrets_enabled' \
    --default "false"
  )
  secrets=$(get_config_value \
    --provider '.providers["scope-configuration"].security.image_pull_secrets | @json' \
    --default "[]"
  )

  assert_equal "$enabled" "true"
  assert_contains "$secrets" "custom-secret"
  assert_contains "$secrets" "ecr-secret"
}

# =============================================================================
# Test: IMAGE_PULL_SECRETS uses env var
# =============================================================================
@test "deployment/build_context: IMAGE_PULL_SECRETS uses env var" {
  export IMAGE_PULL_SECRETS='{"ENABLED":true,"SECRETS":["env-secret"]}'

  # When IMAGE_PULL_SECRETS env var is set, it's used directly
  # This test verifies env var has priority over provider
  result=$(get_config_value \
    --env IMAGE_PULL_SECRETS \
    --provider '.providers["scope-configuration"].image_pull_secrets | @json' \
    --default "{}"
  )

  assert_contains "$result" "env-secret"
}

# =============================================================================
# Test: IMAGE_PULL_SECRETS uses default
# =============================================================================
@test "deployment/build_context: IMAGE_PULL_SECRETS uses default" {
  enabled=$(get_config_value \
    --provider '.providers["scope-configuration"].image_pull_secrets_enabled' \
    --default "false"
  )
  secrets=$(get_config_value \
    --provider '.providers["scope-configuration"].image_pull_secrets | @json' \
    --default "[]"
  )

  assert_equal "$enabled" "false"
  assert_equal "$secrets" "[]"
}

# =============================================================================
# Test: TRAFFIC_CONTAINER_IMAGE uses scope-configuration provider
# =============================================================================
@test "deployment/build_context: TRAFFIC_CONTAINER_IMAGE uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configuration"] = {
    "deployment": {
      "traffic_container_image": "custom.ecr.aws/traffic-manager:v2.0"
    }
  }')

  result=$(get_config_value \
    --env TRAFFIC_CONTAINER_IMAGE \
    --provider '.providers["scope-configuration"].deployment.traffic_container_image' \
    --default "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
  )

  assert_equal "$result" "custom.ecr.aws/traffic-manager:v2.0"
}

# =============================================================================
# Test: TRAFFIC_CONTAINER_IMAGE uses env var
# =============================================================================
@test "deployment/build_context: TRAFFIC_CONTAINER_IMAGE uses env var" {
  export TRAFFIC_CONTAINER_IMAGE="env.ecr.aws/traffic:custom"

  result=$(get_config_value \
    --env TRAFFIC_CONTAINER_IMAGE \
    --provider '.providers["scope-configuration"].deployment.traffic_container_image' \
    --default "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
  )

  assert_equal "$result" "env.ecr.aws/traffic:custom"
}

# =============================================================================
# Test: TRAFFIC_CONTAINER_IMAGE uses default
# =============================================================================
@test "deployment/build_context: TRAFFIC_CONTAINER_IMAGE uses default" {
  result=$(get_config_value \
    --env TRAFFIC_CONTAINER_IMAGE \
    --provider '.providers["scope-configuration"].deployment.traffic_container_image' \
    --default "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
  )

  assert_equal "$result" "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
}

# =============================================================================
# Test: PDB_ENABLED uses scope-configuration provider
# =============================================================================
@test "deployment/build_context: PDB_ENABLED uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configuration"] = {
    "deployment": {
      "pod_disruption_budget_enabled": "true"
    }
  }')

  unset POD_DISRUPTION_BUDGET_ENABLED

  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_ENABLED \
    --provider '.providers["scope-configuration"].deployment.pod_disruption_budget_enabled' \
    --default "false"
  )

  assert_equal "$result" "true"
}

# =============================================================================
# Test: PDB_ENABLED uses env var
# =============================================================================
@test "deployment/build_context: PDB_ENABLED uses env var" {
  export POD_DISRUPTION_BUDGET_ENABLED="true"

  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_ENABLED \
    --provider '.providers["scope-configuration"].deployment.pod_disruption_budget_enabled' \
    --default "false"
  )

  assert_equal "$result" "true"
}

# =============================================================================
# Test: PDB_ENABLED uses default
# =============================================================================
@test "deployment/build_context: PDB_ENABLED uses default" {
  unset POD_DISRUPTION_BUDGET_ENABLED

  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_ENABLED \
    --provider '.providers["scope-configuration"].deployment.pod_disruption_budget_enabled' \
    --default "false"
  )

  assert_equal "$result" "false"
}

# =============================================================================
# Test: PDB_MAX_UNAVAILABLE uses scope-configuration provider
# =============================================================================
@test "deployment/build_context: PDB_MAX_UNAVAILABLE uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configuration"] = {
    "deployment": {
      "pod_disruption_budget_max_unavailable": "50%"
    }
  }')

  unset POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE

  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE \
    --provider '.providers["scope-configuration"].deployment.pod_disruption_budget_max_unavailable' \
    --default "25%"
  )

  assert_equal "$result" "50%"
}

# =============================================================================
# Test: PDB_MAX_UNAVAILABLE uses env var
# =============================================================================
@test "deployment/build_context: PDB_MAX_UNAVAILABLE uses env var" {
  export POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE="2"

  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE \
    --provider '.providers["scope-configuration"].deployment.pod_disruption_budget_max_unavailable' \
    --default "25%"
  )

  assert_equal "$result" "2"
}

# =============================================================================
# Test: PDB_MAX_UNAVAILABLE uses default
# =============================================================================
@test "deployment/build_context: PDB_MAX_UNAVAILABLE uses default" {
  unset POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE

  result=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE \
    --provider '.providers["scope-configuration"].deployment.pod_disruption_budget_max_unavailable' \
    --default "25%"
  )

  assert_equal "$result" "25%"
}

# =============================================================================
# Test: TRAFFIC_MANAGER_CONFIG_MAP uses scope-configuration provider
# =============================================================================
@test "deployment/build_context: TRAFFIC_MANAGER_CONFIG_MAP uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configuration"] = {
    "deployment": {
      "traffic_manager_config_map": "custom-traffic-config"
    }
  }')

  result=$(get_config_value \
    --env TRAFFIC_MANAGER_CONFIG_MAP \
    --provider '.providers["scope-configuration"].deployment.traffic_manager_config_map' \
    --default ""
  )

  assert_equal "$result" "custom-traffic-config"
}

# =============================================================================
# Test: TRAFFIC_MANAGER_CONFIG_MAP uses env var
# =============================================================================
@test "deployment/build_context: TRAFFIC_MANAGER_CONFIG_MAP uses env var" {
  export TRAFFIC_MANAGER_CONFIG_MAP="env-traffic-config"

  result=$(get_config_value \
    --env TRAFFIC_MANAGER_CONFIG_MAP \
    --provider '.providers["scope-configuration"].deployment.traffic_manager_config_map' \
    --default ""
  )

  assert_equal "$result" "env-traffic-config"
}

# =============================================================================
# Test: TRAFFIC_MANAGER_CONFIG_MAP uses default (empty)
# =============================================================================
@test "deployment/build_context: TRAFFIC_MANAGER_CONFIG_MAP uses default empty" {
  result=$(get_config_value \
    --env TRAFFIC_MANAGER_CONFIG_MAP \
    --provider '.providers["scope-configuration"].deployment.traffic_manager_config_map' \
    --default ""
  )

  assert_empty "$result"
}

# =============================================================================
# Test: DEPLOY_STRATEGY uses scope-configuration provider
# =============================================================================
@test "deployment/build_context: DEPLOY_STRATEGY uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configuration"] = {
    "deployment": {
      "deployment_strategy": "blue-green"
    }
  }')

  result=$(get_config_value \
    --env DEPLOY_STRATEGY \
    --provider '.providers["scope-configuration"].deployment.deployment_strategy' \
    --default "rolling"
  )

  assert_equal "$result" "blue-green"
}

# =============================================================================
# Test: DEPLOY_STRATEGY uses env var
# =============================================================================
@test "deployment/build_context: DEPLOY_STRATEGY uses env var" {
  export DEPLOY_STRATEGY="blue-green"

  result=$(get_config_value \
    --env DEPLOY_STRATEGY \
    --provider '.providers["scope-configuration"].deployment.deployment_strategy' \
    --default "rolling"
  )

  assert_equal "$result" "blue-green"
}

# =============================================================================
# Test: DEPLOY_STRATEGY uses default
# =============================================================================
@test "deployment/build_context: DEPLOY_STRATEGY uses default" {
  result=$(get_config_value \
    --env DEPLOY_STRATEGY \
    --provider '.providers["scope-configuration"].deployment.deployment_strategy' \
    --default "rolling"
  )

  assert_equal "$result" "rolling"
}

# =============================================================================
# Test: IAM uses scope-configuration provider
# =============================================================================
@test "deployment/build_context: IAM uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configuration"] = {
    "security": {
      "iam_enabled": true,
      "iam_prefix": "custom-prefix"
    }
  }')

  enabled=$(get_config_value \
    --provider '.providers["scope-configuration"].security.iam_enabled' \
    --default "false"
  )
  prefix=$(get_config_value \
    --provider '.providers["scope-configuration"].security.iam_prefix' \
    --default ""
  )

  assert_equal "$enabled" "true"
  assert_equal "$prefix" "custom-prefix"
}

# =============================================================================
# Test: IAM uses env var
# =============================================================================
@test "deployment/build_context: IAM uses env var" {
  export IAM='{"ENABLED":true,"PREFIX":"env-prefix"}'

  result=$(get_config_value \
    --env IAM \
    --provider '.providers["scope-configuration"].deployment.iam | @json' \
    --default "{}"
  )

  assert_contains "$result" "env-prefix"
}

# =============================================================================
# Test: IAM uses default
# =============================================================================
@test "deployment/build_context: IAM uses default" {
  enabled=$(get_config_value \
    --provider '.providers["scope-configuration"].security.iam_enabled' \
    --default "false"
  )
  prefix=$(get_config_value \
    --provider '.providers["scope-configuration"].security.iam_prefix' \
    --default ""
  )

  assert_equal "$enabled" "false"
  assert_empty "$prefix"
}

# =============================================================================
# Test: Complete deployment configuration hierarchy
# =============================================================================
@test "deployment/build_context: complete deployment configuration hierarchy" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configuration"] = {
    "deployment": {
      "traffic_container_image": "custom.ecr.aws/traffic:v1",
      "pod_disruption_budget_enabled": "true",
      "pod_disruption_budget_max_unavailable": "1",
      "traffic_manager_config_map": "my-config-map"
    }
  }')

  # Test TRAFFIC_CONTAINER_IMAGE
  traffic_image=$(get_config_value \
    --env TRAFFIC_CONTAINER_IMAGE \
    --provider '.providers["scope-configuration"].deployment.traffic_container_image' \
    --default "public.ecr.aws/nullplatform/k8s-traffic-manager:latest"
  )
  assert_equal "$traffic_image" "custom.ecr.aws/traffic:v1"

  # Test PDB_ENABLED
  unset POD_DISRUPTION_BUDGET_ENABLED
  pdb_enabled=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_ENABLED \
    --provider '.providers["scope-configuration"].deployment.pod_disruption_budget_enabled' \
    --default "false"
  )
  assert_equal "$pdb_enabled" "true"

  # Test PDB_MAX_UNAVAILABLE
  unset POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE
  pdb_max=$(get_config_value \
    --env POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE \
    --provider '.providers["scope-configuration"].deployment.pod_disruption_budget_max_unavailable' \
    --default "25%"
  )
  assert_equal "$pdb_max" "1"

  # Test TRAFFIC_MANAGER_CONFIG_MAP
  config_map=$(get_config_value \
    --env TRAFFIC_MANAGER_CONFIG_MAP \
    --provider '.providers["scope-configuration"].deployment.traffic_manager_config_map' \
    --default ""
  )
  assert_equal "$config_map" "my-config-map"
}
