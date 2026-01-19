#!/usr/bin/env bats
# =============================================================================
# Unit tests for build_context - configuration value resolution
# =============================================================================

setup() {
  # Get project root directory (tests are in k8s/scope/tests, so go up 3 levels)
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Source get_config_value utility
  source "$PROJECT_ROOT/k8s/utils/get_config_value"

  # Mock kubectl to avoid actual cluster operations
  kubectl() {
    case "$1" in
      get)
        if [ "$2" = "namespace" ]; then
          # Simulate namespace exists
          return 0
        fi
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  # Set required environment variables
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export SCOPE_ID="test-scope-123"

  # Default values from values.yaml
  export K8S_NAMESPACE="nullplatform"
  export CREATE_K8S_NAMESPACE_IF_NOT_EXIST="true"
  export DOMAIN="nullapps.io"
  export USE_ACCOUNT_SLUG="false"
  export PUBLIC_GATEWAY_NAME="gateway-public"
  export PRIVATE_GATEWAY_NAME="gateway-internal"
  export K8S_MODIFIERS="{}"

  # Base CONTEXT with required fields
  export CONTEXT='{
    "scope": {
      "id": "test-scope-123",
      "nrn": "nrn:organization=100:account=200:namespace=300:application=400",
      "domain": "test.nullapps.io",
      "capabilities": {
        "visibility": "public"
      }
    },
    "namespace": {
      "slug": "test-namespace"
    },
    "application": {
      "slug": "test-app"
    },
    "providers": {
      "cloud-providers": {
        "account": {
          "region": "us-east-1"
        },
        "networking": {
          "domain_name": "cloud-domain.io",
          "application_domain": "false"
        }
      },
      "container-orchestration": {
        "cluster": {
          "namespace": "default-namespace"
        },
        "gateway": {
          "public_name": "co-gateway-public",
          "private_name": "co-gateway-private"
        },
        "balancer": {
          "public_name": "co-balancer-public",
          "private_name": "co-balancer-private"
        }
      }
    }
  }'
}

teardown() {
  # Clean up environment variables
  unset NAMESPACE_OVERRIDE
  unset CREATE_K8S_NAMESPACE_IF_NOT_EXIST
  unset K8S_MODIFIERS
}

# =============================================================================
# Test: K8S_NAMESPACE uses scope-configuration provider first
# =============================================================================
@test "build_context: K8S_NAMESPACE uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "cluster": {
      "namespace": "scope-config-ns"
    }
  }')

  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["scope-configurations"].cluster.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "$K8S_NAMESPACE"
  )

  assert_equal "$result" "scope-config-ns"
}

# =============================================================================
# Test: K8S_NAMESPACE falls back to container-orchestration
# =============================================================================
@test "build_context: K8S_NAMESPACE falls back to container-orchestration" {
  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["scope-configurations"].cluster.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "$K8S_NAMESPACE"
  )

  assert_equal "$result" "default-namespace"
}

# =============================================================================
# Test: K8S_NAMESPACE - provider wins over env var
# =============================================================================
@test "build_context: K8S_NAMESPACE provider wins over NAMESPACE_OVERRIDE env var" {
  export NAMESPACE_OVERRIDE="env-override-ns"

  # Set up context with namespace in container-orchestration provider
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["container-orchestration"] = {
    "cluster": {
      "namespace": "provider-namespace"
    }
  }')

  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["scope-configurations"].cluster.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "$K8S_NAMESPACE"
  )

  assert_equal "$result" "provider-namespace"
}

# =============================================================================
# Test: K8S_NAMESPACE uses env var when no provider
# =============================================================================
@test "build_context: K8S_NAMESPACE uses NAMESPACE_OVERRIDE when no provider" {
  export NAMESPACE_OVERRIDE="env-override-ns"

  # Remove namespace from providers so env var can win
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.namespace)')

  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["scope-configurations"].cluster.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "$K8S_NAMESPACE"
  )

  assert_equal "$result" "env-override-ns"
}

# =============================================================================
# Test: K8S_NAMESPACE uses values.yaml default
# =============================================================================
@test "build_context: K8S_NAMESPACE uses values.yaml default" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.namespace)')

  result=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["scope-configurations"].cluster.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "$K8S_NAMESPACE"
  )

  assert_equal "$result" "nullplatform"
}

# =============================================================================
# Test: REGION only uses cloud-providers (not scope-configuration)
# =============================================================================
@test "build_context: REGION only uses cloud-providers" {
  # Set up context with region in cloud-providers
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["cloud-providers"] = {
    "account": {
      "region": "eu-west-1"
    }
  }')

  result=$(get_config_value \
    --provider '.providers["cloud-providers"].account.region' \
    --default "us-east-1"
  )

  assert_equal "$result" "eu-west-1"
}

# =============================================================================
# Test: REGION falls back to default when cloud-providers not available
# =============================================================================
@test "build_context: REGION falls back to default" {
  result=$(get_config_value \
    --provider '.providers["cloud-providers"].account.region' \
    --default "us-east-1"
  )

  assert_equal "$result" "us-east-1"
}

# =============================================================================
# Test: USE_ACCOUNT_SLUG uses scope-configuration provider
# =============================================================================
@test "build_context: USE_ACCOUNT_SLUG uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "networking": {
      "application_domain": "true"
    }
  }')

  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.application_domain' \
    --provider '.providers["cloud-providers"].networking.application_domain' \
    --default "$USE_ACCOUNT_SLUG"
  )

  assert_equal "$result" "true"
}

# =============================================================================
# Test: DOMAIN (public) uses scope-configuration provider
# =============================================================================
@test "build_context: DOMAIN (public) uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "networking": {
      "domain_name": "scope-config-domain.io"
    }
  }')

  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.domain_name' \
    --provider '.providers["cloud-providers"].networking.domain_name' \
    --default "$DOMAIN"
  )

  assert_equal "$result" "scope-config-domain.io"
}

# =============================================================================
# Test: DOMAIN (public) falls back to cloud-providers
# =============================================================================
@test "build_context: DOMAIN (public) falls back to cloud-providers" {
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.domain_name' \
    --provider '.providers["cloud-providers"].networking.domain_name' \
    --default "$DOMAIN"
  )

  assert_equal "$result" "cloud-domain.io"
}

# =============================================================================
# Test: DOMAIN (private) uses scope-configuration provider
# =============================================================================
@test "build_context: DOMAIN (private) uses scope-configuration private domain" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.visibility = "private" |
    .providers["scope-configurations"] = {
    "networking": {
      "private_domain_name": "private-scope.io"
      }
    }')

  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.private_domain_name' \
    --provider '.providers["cloud-providers"].networking.private_domain_name' \
    --provider '.providers["scope-configurations"].networking.domain_name' \
    --provider '.providers["cloud-providers"].networking.domain_name' \
    --default "${PRIVATE_DOMAIN:-$DOMAIN}"
  )

  assert_equal "$result" "private-scope.io"
}

# =============================================================================
# Test: GATEWAY_NAME (public) uses scope-configuration provider
# =============================================================================
@test "build_context: GATEWAY_NAME (public) uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "networking": {
      "gateway_public_name": "scope-gateway-public"
    }
  }')

  GATEWAY_DEFAULT="${PUBLIC_GATEWAY_NAME:-gateway-public}"
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.gateway_public_name' \
    --provider '.providers["container-orchestration"].gateway.public_name' \
    --default "$GATEWAY_DEFAULT"
  )

  assert_equal "$result" "scope-gateway-public"
}

# =============================================================================
# Test: GATEWAY_NAME (public) falls back to container-orchestration
# =============================================================================
@test "build_context: GATEWAY_NAME (public) falls back to container-orchestration" {
  GATEWAY_DEFAULT="${PUBLIC_GATEWAY_NAME:-gateway-public}"
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.gateway_public_name' \
    --provider '.providers["container-orchestration"].gateway.public_name' \
    --default "$GATEWAY_DEFAULT"
  )

  assert_equal "$result" "co-gateway-public"
}

# =============================================================================
# Test: GATEWAY_NAME (private) uses scope-configuration provider
# =============================================================================
@test "build_context: GATEWAY_NAME (private) uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "networking": {
      "gateway_private_name": "scope-gateway-private"
    }
  }')

  GATEWAY_DEFAULT="${PRIVATE_GATEWAY_NAME:-gateway-internal}"
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.gateway_private_name' \
    --provider '.providers["container-orchestration"].gateway.private_name' \
    --default "$GATEWAY_DEFAULT"
  )

  assert_equal "$result" "scope-gateway-private"
}

# =============================================================================
# Test: ALB_NAME (public) uses scope-configuration provider
# =============================================================================
@test "build_context: ALB_NAME (public) uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "networking": {
      "balancer_public_name": "scope-balancer-public"
    }
  }')

  ALB_NAME="k8s-nullplatform-internet-facing"
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.balancer_public_name' \
    --provider '.providers["container-orchestration"].balancer.public_name' \
    --default "$ALB_NAME"
  )

  assert_equal "$result" "scope-balancer-public"
}

# =============================================================================
# Test: ALB_NAME (private) uses scope-configuration provider
# =============================================================================
@test "build_context: ALB_NAME (private) uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "networking": {
      "balancer_private_name": "scope-balancer-private"
    }
  }')

  ALB_NAME="k8s-nullplatform-internal"
  result=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.balancer_private_name' \
    --provider '.providers["container-orchestration"].balancer.private_name' \
    --default "$ALB_NAME"
  )

  assert_equal "$result" "scope-balancer-private"
}

# =============================================================================
# Test: CREATE_K8S_NAMESPACE_IF_NOT_EXIST uses scope-configuration provider
# =============================================================================
@test "build_context: CREATE_K8S_NAMESPACE_IF_NOT_EXIST uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "cluster": {
      "create_namespace_if_not_exist": "false"
    }
  }')

  # Unset the env var to test provider precedence
  unset CREATE_K8S_NAMESPACE_IF_NOT_EXIST

  result=$(get_config_value \
    --env CREATE_K8S_NAMESPACE_IF_NOT_EXIST \
    --provider '.providers["scope-configurations"].cluster.create_namespace_if_not_exist' \
    --default "true"
  )

  assert_equal "$result" "false"
}

# =============================================================================
# Test: K8S_MODIFIERS uses scope-configuration provider
# =============================================================================
@test "build_context: K8S_MODIFIERS uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "object_modifiers": {
      "modifiers": {
        "global": {
          "labels": {
            "environment": "production"
          }
        }
      }
    }
  }')

  # Unset the env var to test provider precedence
  unset K8S_MODIFIERS

  result=$(get_config_value \
    --env K8S_MODIFIERS \
    --provider '.providers["scope-configurations"].object_modifiers | @json' \
    --default "{}"
  )

  # Parse and verify it's valid JSON with the expected structure
  assert_contains "$result" "production"
  assert_contains "$result" "environment"
}

# =============================================================================
# Test: K8S_MODIFIERS uses env var
# =============================================================================
@test "build_context: K8S_MODIFIERS uses env var" {
  export K8S_MODIFIERS='{"custom":"value"}'

  result=$(get_config_value \
    --env K8S_MODIFIERS \
    --provider '.providers["scope-configurations"].object_modifiers.modifiers | @json' \
    --default "${K8S_MODIFIERS:-"{}"}"
  )

  assert_contains "$result" "custom"
  assert_contains "$result" "value"
}

# =============================================================================
# Test: Complete hierarchy for all configuration values
# =============================================================================
@test "build_context: complete configuration hierarchy works end-to-end" {
  # Set up a complete scope-configuration provider
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "cluster": {
      "namespace": "scope-ns",
      "create_namespace_if_not_exist": "false",
      "region": "ap-south-1"
    },
    "networking": {
      "domain_name": "scope-domain.io",
      "application_domain": "true",
      "gateway_public_name": "scope-gw-public",
      "balancer_public_name": "scope-alb-public"
    },
    "object_modifiers": {
      "modifiers": {"test": "value"}
    }
  }')

  # Test K8S_NAMESPACE
  k8s_namespace=$(get_config_value \
    --env NAMESPACE_OVERRIDE \
    --provider '.providers["scope-configurations"].cluster.namespace' \
    --provider '.providers["container-orchestration"].cluster.namespace' \
    --default "$K8S_NAMESPACE"
  )
  assert_equal "$k8s_namespace" "scope-ns"

  # Test REGION
  region=$(get_config_value \
    --provider '.providers["scope-configurations"].cluster.region' \
    --provider '.providers["cloud-providers"].account.region' \
    --default "us-east-1"
  )
  assert_equal "$region" "ap-south-1"

  # Test DOMAIN
  domain=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.domain_name' \
    --provider '.providers["cloud-providers"].networking.domain_name' \
    --default "$DOMAIN"
  )
  assert_equal "$domain" "scope-domain.io"

  # Test USE_ACCOUNT_SLUG
  use_account_slug=$(get_config_value \
    --provider '.providers["scope-configurations"].networking.application_domain' \
    --provider '.providers["cloud-providers"].networking.application_domain' \
    --default "$USE_ACCOUNT_SLUG"
  )
  assert_equal "$use_account_slug" "true"
}

# =============================================================================
# Test: DNS_TYPE uses scope-configuration provider
# =============================================================================
@test "build_context: DNS_TYPE uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "networking": {
      "dns_type": "azure"
    }
  }')

  result=$(get_config_value \
    --env DNS_TYPE \
    --provider '.providers["scope-configurations"].networking.dns_type' \
    --default "route53"
  )

  assert_equal "$result" "azure"
}

# =============================================================================
# Test: DNS_TYPE uses default
# =============================================================================
@test "build_context: DNS_TYPE uses default" {
  result=$(get_config_value \
    --env DNS_TYPE \
    --provider '.providers["scope-configurations"].networking.dns_type' \
    --default "route53"
  )

  assert_equal "$result" "route53"
}

# =============================================================================
# Test: ALB_RECONCILIATION_ENABLED uses scope-configuration provider
# =============================================================================
@test "build_context: ALB_RECONCILIATION_ENABLED uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "networking": {
      "alb_reconciliation_enabled": "true"
    }
  }')

  result=$(get_config_value \
    --env ALB_RECONCILIATION_ENABLED \
    --provider '.providers["scope-configurations"].networking.alb_reconciliation_enabled' \
    --default "false"
  )

  assert_equal "$result" "true"
}

# =============================================================================
# Test: DEPLOYMENT_MAX_WAIT_IN_SECONDS uses scope-configuration provider
# =============================================================================
@test "build_context: DEPLOYMENT_MAX_WAIT_IN_SECONDS uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "deployment_max_wait_seconds": 900
  }')

  result=$(get_config_value \
    --env DEPLOYMENT_MAX_WAIT_IN_SECONDS \
    --provider '.providers["scope-configurations"].deployment_max_wait_seconds' \
    --default "600"
  )

  assert_equal "$result" "900"
}

# =============================================================================
# Test: MANIFEST_BACKUP uses scope-configuration provider
# =============================================================================
@test "build_context: MANIFEST_BACKUP uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "manifest_backup_enabled": true,
    "manifest_backup_type": "s3",
    "manifest_backup_bucket": "my-bucket"
  }')

  enabled=$(get_config_value \
    --provider '.providers["scope-configurations"].manifest_backup_enabled' \
    --default "false"
  )
  type=$(get_config_value \
    --provider '.providers["scope-configurations"].manifest_backup_type' \
    --default ""
  )
  bucket=$(get_config_value \
    --provider '.providers["scope-configurations"].manifest_backup_bucket' \
    --default ""
  )

  assert_equal "$enabled" "true"
  assert_equal "$type" "s3"
  assert_equal "$bucket" "my-bucket"
}

# =============================================================================
# Test: VAULT_ADDR uses scope-configuration provider
# =============================================================================
@test "build_context: VAULT_ADDR uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "vault_address": "https://vault.example.com"
  }')

  result=$(get_config_value \
    --env VAULT_ADDR \
    --provider '.providers["scope-configurations"].vault_address' \
    --default ""
  )

  assert_equal "$result" "https://vault.example.com"
}

# =============================================================================
# Test: VAULT_TOKEN uses scope-configuration provider
# =============================================================================
@test "build_context: VAULT_TOKEN uses scope-configuration provider" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "vault_token": "s.xxxxxxxxxxxxxxx"
  }')

  result=$(get_config_value \
    --env VAULT_TOKEN \
    --provider '.providers["scope-configurations"].vault_token' \
    --default ""
  )

  assert_equal "$result" "s.xxxxxxxxxxxxxxx"
}
