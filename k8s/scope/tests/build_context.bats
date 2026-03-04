#!/usr/bin/env bats
# =============================================================================
# Unit tests for build_context
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$PROJECT_ROOT/k8s/utils/get_config_value"

  export SCRIPT="$PROJECT_ROOT/k8s/scope/build_context"

  # Mock kubectl - namespace exists by default
  kubectl() {
    case "$1" in
      get)
        if [ "$2" = "namespace" ]; then
          return 0
        fi
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  # Create temp output directory
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SERVICE_PATH="$PROJECT_ROOT/k8s"

  # Default values from values.yaml
  export K8S_NAMESPACE="nullplatform"
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
  rm -rf "$NP_OUTPUT_DIR"
  unset NAMESPACE_OVERRIDE
  unset K8S_MODIFIERS
  unset -f kubectl
}

# =============================================================================
# Success flow - logging
# =============================================================================
@test "build_context: success flow - displays all messages" {
  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Validating namespace 'default-namespace' exists..."
  assert_contains "$output" "✅ Namespace 'default-namespace' exists"
  assert_contains "$output" "📋 Scope: test-scope-123 | Visibility: public | Domain: test.nullapps.io"
  assert_contains "$output" "📋 Namespace: default-namespace | Region: us-east-1 | Gateway: co-gateway-public | ALB: co-balancer-public"
  assert_contains "$output" "✅ Scope context built successfully"
}

# =============================================================================
# Full CONTEXT validation (public visibility)
# =============================================================================
@test "build_context: produces complete CONTEXT with all expected fields (public)" {
  source "$SCRIPT"

  local expected_json='{
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
    },
    "ingress_visibility": "internet-facing",
    "k8s_namespace": "default-namespace",
    "region": "us-east-1",
    "gateway_name": "co-gateway-public",
    "alb_name": "co-balancer-public",
    "component": "test-namespace-test-app",
    "k8s_modifiers": {}
  }'

  assert_json_equal "$CONTEXT" "$expected_json" "Complete CONTEXT (public)"
}

# =============================================================================
# Full CONTEXT validation (private visibility)
# =============================================================================
@test "build_context: produces complete CONTEXT with all expected fields (private)" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.visibility = "private"')

  source "$SCRIPT"

  local expected_json='{
    "scope": {
      "id": "test-scope-123",
      "nrn": "nrn:organization=100:account=200:namespace=300:application=400",
      "domain": "test.nullapps.io",
      "capabilities": {
        "visibility": "private"
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
    },
    "ingress_visibility": "internal",
    "k8s_namespace": "default-namespace",
    "region": "us-east-1",
    "gateway_name": "co-gateway-private",
    "alb_name": "co-balancer-private",
    "component": "test-namespace-test-app",
    "k8s_modifiers": {}
  }'

  assert_json_equal "$CONTEXT" "$expected_json" "Complete CONTEXT (private)"
}

@test "build_context: private visibility displays correct summary" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.visibility = "private"')

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Scope: test-scope-123 | Visibility: private | Domain: test.nullapps.io"
  assert_contains "$output" "📋 Namespace: default-namespace | Region: us-east-1 | Gateway: co-gateway-private | ALB: co-balancer-private"
}

# =============================================================================
# Exported variables
# =============================================================================
@test "build_context: exports NRN IDs from scope nrn" {
  source "$SCRIPT"

  assert_equal "$ORGANIZATION_ID" "100"
  assert_equal "$ACCOUNT_ID" "200"
  assert_equal "$NAMESPACE_ID" "300"
  assert_equal "$APPLICATION_ID" "400"
}

@test "build_context: exports all expected environment variables" {
  source "$SCRIPT"

  assert_equal "$DNS_TYPE" "route53"
  assert_equal "$ALB_RECONCILIATION_ENABLED" "false"
  assert_equal "$DEPLOYMENT_MAX_WAIT_IN_SECONDS" "600"
  assert_equal "$SCOPE_VISIBILITY" "public"
  assert_equal "$SCOPE_DOMAIN" "test.nullapps.io"
  assert_equal "$INGRESS_VISIBILITY" "internet-facing"
  assert_equal "$GATEWAY_NAME" "co-gateway-public"
  assert_equal "$REGION" "us-east-1"
}

@test "build_context: creates OUTPUT_DIR" {
  source "$SCRIPT"

  assert_equal "$OUTPUT_DIR" "$NP_OUTPUT_DIR/output/test-scope-123"
  assert_directory_exists "$OUTPUT_DIR"
}

@test "build_context: uses SERVICE_PATH when NP_OUTPUT_DIR is not set" {
  unset NP_OUTPUT_DIR

  source "$SCRIPT"

  assert_equal "$OUTPUT_DIR" "$SERVICE_PATH/output/test-scope-123"
  assert_directory_exists "$OUTPUT_DIR"
}

# =============================================================================
# Namespace validation
# =============================================================================
@test "build_context: creates namespace when it does not exist and creation is enabled" {
  kubectl() {
    case "$1" in
      get)
        if [ "$2" = "namespace" ]; then
          return 1
        fi
        ;;
      *)
        echo "kubectl $*"
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Validating namespace 'default-namespace' exists..."
  assert_contains "$output" "❌ Namespace 'default-namespace' does not exist in the cluster"
  assert_contains "$output" "📝 Creating namespace 'default-namespace'..."
  assert_contains "$output" "✅ Namespace 'default-namespace' created successfully"
}

@test "build_context: fails when namespace does not exist and creation is disabled" {
  kubectl() {
    if [ "$1" = "get" ] && [ "$2" = "namespace" ]; then
      return 1
    fi
    return 0
  }
  export -f kubectl
  export CREATE_K8S_NAMESPACE_IF_NOT_EXIST="false"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Namespace 'default-namespace' does not exist in the cluster"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The namespace does not exist and automatic creation is disabled"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Create the namespace manually: kubectl create namespace default-namespace"
  assert_contains "$output" "Or set CREATE_K8S_NAMESPACE_IF_NOT_EXIST=true in values.yaml"
}

@test "build_context: CREATE_K8S_NAMESPACE_IF_NOT_EXIST resolves from provider" {
  kubectl() {
    if [ "$1" = "get" ] && [ "$2" = "namespace" ]; then
      return 1
    fi
    return 0
  }
  export -f kubectl
  unset CREATE_K8S_NAMESPACE_IF_NOT_EXIST

  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "cluster": {
      "create_namespace_if_not_exist": "false"
    }
  }')

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Namespace 'default-namespace' does not exist in the cluster"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The namespace does not exist and automatic creation is disabled"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Create the namespace manually: kubectl create namespace default-namespace"
  assert_contains "$output" "Or set CREATE_K8S_NAMESPACE_IF_NOT_EXIST=true in values.yaml"
}

# =============================================================================
# COMPONENT truncation
# =============================================================================
@test "build_context: COMPONENT truncates to 63 chars ending with alphanumeric" {
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .namespace.slug = "very-long-namespace-slug-that-goes-on" |
    .application.slug = "and-on-with-app-slug-extending-past-limit"
  ')

  source "$SCRIPT"

  local component=$(echo "$CONTEXT" | jq -r .component)
  [ ${#component} -le 63 ]
  [[ "$component" =~ [a-zA-Z0-9]$ ]]
}

# =============================================================================
# Scope-configurations override (end-to-end)
# =============================================================================
@test "build_context: scope-configurations override produces correct CONTEXT" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {
    "cluster": {
      "namespace": "scope-ns"
    },
    "networking": {
      "domain_name": "scope-domain.io",
      "application_domain": "true",
      "gateway_public_name": "scope-gw-public",
      "balancer_public_name": "scope-alb-public"
    }
  }')

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -r .k8s_namespace)" "scope-ns"
  assert_equal "$(echo "$CONTEXT" | jq -r .gateway_name)" "scope-gw-public"
  assert_equal "$(echo "$CONTEXT" | jq -r .alb_name)" "scope-alb-public"
  assert_equal "$GATEWAY_NAME" "scope-gw-public"
}
