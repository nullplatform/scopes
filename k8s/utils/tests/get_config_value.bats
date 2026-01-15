#!/usr/bin/env bats
# =============================================================================
# Unit tests for get_config_value - configuration value priority hierarchy
# =============================================================================

setup() {
  # Get project root directory (tests are in k8s/utils/tests, so go up 3 levels)
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Source the get_config_value file we're testing (it's one level up from test directory)
  source "$BATS_TEST_DIRNAME/../get_config_value"

  # Setup test CONTEXT for provider tests
  export CONTEXT='{
    "providers": {
      "scope-configurations": {
        "kubernetes": {
          "namespace": "scope-config-namespace"
        },
        "region": "us-west-2"
      },
      "container-orchestration": {
        "cluster": {
          "namespace": "container-orch-namespace"
        }
      },
      "cloud-providers": {
        "account": {
          "region": "eu-west-1"
        }
      }
    }
  }'
}

teardown() {
  # Clean up any env vars set during tests
  unset TEST_ENV_VAR
  unset NAMESPACE_OVERRIDE
}

# =============================================================================
# Test: Provider has highest priority over env variable
# =============================================================================
@test "get_config_value: provider has highest priority over env variable" {
  export TEST_ENV_VAR="env-value"

  result=$(get_config_value \
    --env TEST_ENV_VAR \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --default "default-value")

  assert_equal "$result" "scope-config-namespace"
}

# =============================================================================
# Test: Provider value used when env var is not set
# =============================================================================
@test "get_config_value: uses provider when env var not set" {
  result=$(get_config_value \
    --env NON_EXISTENT_VAR \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --default "default-value")

  assert_equal "$result" "scope-config-namespace"
}

# =============================================================================
# Test: Multiple providers - first match wins
# =============================================================================
@test "get_config_value: first provider match wins" {
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "default-value")

  assert_equal "$result" "scope-config-namespace"
}

# =============================================================================
# Test: Falls through to second provider when first doesn't exist
# =============================================================================
@test "get_config_value: falls through to second provider" {
  result=$(get_config_value \
    --provider '.providers["non-existent"].value' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "default-value")

  assert_equal "$result" "container-orch-namespace"
}

# =============================================================================
# Test: Default value used when nothing else matches
# =============================================================================
@test "get_config_value: uses default when no matches" {
  result=$(get_config_value \
    --env NON_EXISTENT_VAR \
    --provider '.providers["non-existent"].value' \
    --default "default-value")

  assert_equal "$result" "default-value"
}

# =============================================================================
# Test: Complete hierarchy - provider1 > provider2 > env > default
# =============================================================================
@test "get_config_value: complete hierarchy provider1 > provider2 > env > default" {
  # Test 1: First provider wins over everything
  export NAMESPACE_OVERRIDE="override-namespace"
  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "default-namespace")
  assert_equal "$result" "scope-config-namespace"

  # Test 2: Second provider wins when first doesn't exist
  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["non-existent"].value' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "default-namespace")
  assert_equal "$result" "container-orch-namespace"

  # Test 3: Env var wins when no providers exist
  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["non-existent1"].value' \
    --provider '.providers["non-existent2"].value' \
    --default "default-namespace")
  assert_equal "$result" "override-namespace"

  # Test 4: Default wins when nothing else exists
  unset NAMESPACE_OVERRIDE
  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["non-existent1"].value' \
    --provider '.providers["non-existent2"].value' \
    --default "default-namespace")
  assert_equal "$result" "default-namespace"
}

# =============================================================================
# Test: Returns empty string when no matches and no default
# =============================================================================
@test "get_config_value: returns empty when no matches and no default" {
  result=$(get_config_value \
    --env NON_EXISTENT_VAR \
    --provider '.providers["non-existent"].value')

  assert_empty "$result"
}

# =============================================================================
# Test: Handles null values from jq correctly
# =============================================================================
@test "get_config_value: ignores null provider values" {
  export CONTEXT='{"providers": {"test": {"value": null}}}'

  result=$(get_config_value \
    --provider '.providers["test"].value' \
    --default "default-value")

  assert_equal "$result" "default-value"
}

# =============================================================================
# Test: Handles empty string env vars correctly (should use them)
# =============================================================================
@test "get_config_value: empty env var is not treated as unset" {
  export TEST_ENV_VAR=""

  result=$(get_config_value \
    --env TEST_ENV_VAR \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --default "default-value")

  # Empty string from env should NOT be used, falls through to provider
  assert_equal "$result" "scope-config-namespace"
}

# =============================================================================
# Test: Real-world scenario - region selection (only from cloud-providers)
# =============================================================================
@test "get_config_value: real-world region selection from cloud-providers only" {
  # Scenario: region should only come from cloud-providers, not scope-configuration
  result=$(get_config_value \
    --provider '.providers["cloud-providers"].account.region' \
    --default "us-east-1")

  assert_equal "$result" "eu-west-1"
}

# =============================================================================
# Test: Real-world scenario - namespace with override (provider wins)
# =============================================================================
@test "get_config_value: real-world namespace - provider wins over NAMESPACE_OVERRIDE" {
  export NAMESPACE_OVERRIDE="prod-override"

  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "default-ns")

  # Provider wins over env var
  assert_equal "$result" "scope-config-namespace"
}

# =============================================================================
# Test: Argument order does NOT affect priority - providers always win
# =============================================================================
@test "get_config_value: argument order does not affect priority - provider first" {
  export TEST_ENV_VAR="env-value"

  # Test with provider before env
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --env TEST_ENV_VAR \
    --default "default-value")

  assert_equal "$result" "scope-config-namespace"
}

@test "get_config_value: argument order does not affect priority - env first" {
  export TEST_ENV_VAR="env-value"

  # Test with env before provider - provider should still win
  result=$(get_config_value \
    --env TEST_ENV_VAR \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --default "default-value")

  assert_equal "$result" "scope-config-namespace"
}

@test "get_config_value: argument order does not affect priority - default first" {
  export TEST_ENV_VAR="env-value"

  # Test with default first - provider should still win
  result=$(get_config_value \
    --default "default-value" \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --env TEST_ENV_VAR)

  assert_equal "$result" "scope-config-namespace"
}

@test "get_config_value: argument order does not affect priority - mixed order" {
  export TEST_ENV_VAR="env-value"

  # Test with mixed order
  result=$(get_config_value \
    --default "default-value" \
    --env TEST_ENV_VAR \
    --provider '.providers["scope-configurations"].kubernetes.namespace')

  assert_equal "$result" "scope-config-namespace"
}

# =============================================================================
# Test: Env var wins when no providers exist, regardless of argument order
# =============================================================================
@test "get_config_value: env var wins when no providers - default first" {
  export TEST_ENV_VAR="env-value"

  result=$(get_config_value \
    --default "default-value" \
    --env TEST_ENV_VAR \
    --provider '.providers["non-existent"].value')

  assert_equal "$result" "env-value"
}

@test "get_config_value: env var wins when no providers - env last" {
  export TEST_ENV_VAR="env-value"

  result=$(get_config_value \
    --provider '.providers["non-existent"].value' \
    --default "default-value" \
    --env TEST_ENV_VAR)

  assert_equal "$result" "env-value"
}

# =============================================================================
# Test: Multiple providers priority order is preserved
# =============================================================================
@test "get_config_value: multiple providers - order matters among providers" {
  # First provider in list should win
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "default-value")

  assert_equal "$result" "scope-config-namespace"
}

@test "get_config_value: multiple providers - reversed order" {
  # First provider in list should still win (container-orchestration comes first)
  result=$(get_config_value \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --provider '.providers["scope-configurations"].kubernetes.namespace' \
    --default "default-value")

  assert_equal "$result" "container-orch-namespace"
}
