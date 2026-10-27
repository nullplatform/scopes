#!/usr/bin/env bats
# =============================================================================
# Unit tests for build_context
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
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
      "slug": "test-scope",
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
      "slug": "test-scope",
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
    "base_domain": "cloud-domain.io",
    "k8s_modifiers": {},
    "service_account": {"enabled": false, "name": ""},
    "names": {
      "deployment": "",
      "service": "",
      "hpa": "",
      "pdb": "",
      "secret": "",
      "secret_files": "",
      "cronjob": "",
      "scope_ingress": "k-8-s-test-scope-test-scope-123-internet-facing",
      "scope_dns": "k8s-test-app-test-scope-test-scope-123-dns",
      "serving_cert": "d-test-scope-123",
      "blue_deployment": "",
      "blue_service": ""
    }
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
      "slug": "test-scope",
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
    "base_domain": "cloud-domain.io",
    "k8s_modifiers": {},
    "service_account": {"enabled": false, "name": ""},
    "names": {
      "deployment": "",
      "service": "",
      "hpa": "",
      "pdb": "",
      "secret": "",
      "secret_files": "",
      "cronjob": "",
      "scope_ingress": "k-8-s-test-scope-test-scope-123-internal",
      "scope_dns": "k8s-test-app-test-scope-test-scope-123-dns",
      "serving_cert": "d-test-scope-123",
      "blue_deployment": "",
      "blue_service": ""
    }
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

# =============================================================================
# Placeholder expansion and service account resolution
# =============================================================================
set_scope_config() {
  export CONTEXT=$(echo "$CONTEXT" | jq --argjson cfg "$1" '
    .scope.dimensions = {"environment": "development"} |
    .providers["scope-configurations"] = $cfg')
}

@test "build_context: expands \${np.*} placeholders in k8s_modifiers" {
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"x": "${np.application_slug}"}}}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -r .k8s_modifiers.deployment.annotations.x)" "test-app"
}

@test "build_context: leaves Go template syntax in k8s_modifiers untouched" {
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"vault": "{{ with secret \"kv/app\" }}{{ .Data.x }}{{ end }}"}}}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -r .k8s_modifiers.deployment.annotations.vault)" '{{ with secret "kv/app" }}{{ .Data.x }}{{ end }}'
}

@test "build_context: fails on unknown placeholder in k8s_modifiers when STRICT_PLACEHOLDERS=true" {
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"x": "${np.nope}"}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ]
  assert_contains "$output" "np.nope"
}

@test "build_context: k8s_modifiers without placeholders are unchanged" {
  export K8S_MODIFIERS='{"deployment":{"labels":{"a":"b"},"annotations":{"c":"d"}}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -cS .k8s_modifiers)" '{"deployment":{"annotations":{"c":"d"},"labels":{"a":"b"}}}'
}

@test "build_context: drops the nested copy the API adds for dotted keys in string maps" {
  set_scope_config '{"object_modifiers": {"deployment": {
    "annotations": {"vault.hashicorp.com/role": "apps", "vault": {"hashicorp": {"com/role": "apps"}}},
    "labels": {"app.kubernetes.io/name": "x", "app": {"kubernetes": {"io/name": "x"}}},
    "nodeselector": {"kubernetes.io/os": "linux", "kubernetes": {"io/os": "linux"}},
    "tolerations": [{"key": "dedicated", "operator": "Exists"}]}}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -cS .k8s_modifiers.deployment)" \
    '{"annotations":{"vault.hashicorp.com/role":"apps"},"labels":{"app.kubernetes.io/name":"x"},"nodeselector":{"kubernetes.io/os":"linux"},"tolerations":[{"key":"dedicated","operator":"Exists"}]}'
}

@test "build_context: drops nested dotted-key copies before expanding placeholders" {
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {
    "vault.hashicorp.com/agent-inject-secret-s": "secret/data/${np.application_slug}",
    "vault": {"hashicorp": {"com/agent-inject-secret-s": "secret/data/${np.application_slug}"}}}}}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -c .k8s_modifiers.deployment.annotations)" \
    '{"vault.hashicorp.com/agent-inject-secret-s":"secret/data/test-app"}'
}

@test "build_context: service_account is disabled by default" {
  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -c .service_account)" '{"enabled":false,"name":""}'
  assert_equal "$SERVICE_ACCOUNT_ENABLED" "false"
  assert_equal "$SERVICE_ACCOUNT_NAME_RESOLVED" ""
}

@test "build_context: disabled service account never evaluates the name template" {
  set_scope_config '{"security": {"service_account_name": "${np.nope}"}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -c .service_account)" '{"enabled":false,"name":""}'
}

@test "build_context: enabled service account defaults to <app_slug>-<scope_id>" {
  set_scope_config '{"security": {"service_account_enabled": "true"}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -c .service_account)" '{"enabled":true,"name":"test-app-test-scope-123"}'
  assert_equal "$SERVICE_ACCOUNT_NAME_RESOLVED" "test-app-test-scope-123"
}

@test "build_context: service account name template resolves placeholders" {
  set_scope_config '{"security": {"service_account_enabled": "true", "service_account_name": "${np.application_slug}-${np.dimension.environment}"}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -r .service_account.name)" "test-app-development"
}

@test "build_context: service account name ending in a dash fails with DNS-1123 message when STRICT_PLACEHOLDERS=true" {
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"security": {"service_account_enabled": "true", "service_account_name": "${np.application_slug}-"}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ]
  assert_contains "$output" "DNS-1123"
}

@test "build_context: service account name with uppercase fails with DNS-1123 message when STRICT_PLACEHOLDERS=true" {
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"security": {"service_account_enabled": "true", "service_account_name": "My-SA"}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ]
  assert_contains "$output" "DNS-1123"
}

@test "build_context: fails on an unresolved service account placeholder when STRICT_PLACEHOLDERS=true" {
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"security": {"service_account_enabled": "true", "service_account_name": "${np.dimension.region}-sa"}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ] || false
  assert_contains "$output" "np.dimension.region"
}

# Tolerant mode (default): actions that do not render pod specs never block on a placeholder.
@test "build_context: tolerant mode expands resolvable placeholders and drops unresolved entries" {
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"vault.hashicorp.com/agent-inject-secret-x": "kv/${np.nope}", "y": "${np.application_slug}"}}}}'

  run bash -c 'source "$SCRIPT" && echo "MODS=$(echo "$CONTEXT" | jq -c .k8s_modifiers)"'

  assert_equal "$status" "0"
  assert_contains "$output" '⚠️  Dropped object_modifiers entries with unresolved placeholder(s) (np.nope): deployment.annotations."vault.hashicorp.com/agent-inject-secret-x"'
  assert_contains "$output" 'MODS={"deployment":{"annotations":{"y":"test-app"}}}'
  [[ "$output" != *'MODS='*'${np.'* ]] || false
  [[ "$output" != *"❌"* ]] || false
}

@test "build_context: tolerant mode logs a single warning for several dropped entries" {
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"a": "${np.nope}", "b": "${np.}"}}, "ingress": {"labels": {"c": "${np.dimension.region}"}}}}'

  run bash -c 'source "$SCRIPT" && echo "MODS=$(echo "$CONTEXT" | jq -c .k8s_modifiers)"'

  assert_equal "$status" "0"
  assert_equal "$(grep -c "Dropped object_modifiers entries" <<<"$output")" "1"
  assert_contains "$output" '(${np.}, np.dimension.region, np.nope): deployment.annotations.a, deployment.annotations.b, ingress.labels.c'
  assert_contains "$output" 'MODS={"deployment":{"annotations":{}},"ingress":{"labels":{}}}'
}

@test "build_context: strict mode fails on a malformed placeholder in k8s_modifiers" {
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"x": "${np.unclosed"}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ] || false
  assert_contains "$output" '${np.unclosed'
}

@test "build_context: tolerant mode disables an unresolvable service account with a warning" {
  set_scope_config '{"security": {"service_account_enabled": "true", "service_account_name": "${np.dimension.region}-sa"}}'

  run bash -c 'source "$SCRIPT" && echo "SA=$(echo "$CONTEXT" | jq -c .service_account) ENABLED=$SERVICE_ACCOUNT_ENABLED"'

  assert_equal "$status" "0"
  assert_contains "$output" "⚠️  Could not resolve the service account name from '\${np.dimension.region}-sa' (unresolved placeholder(s): np.dimension.region); continuing without the per-scope service account for this action (a scope delete leaves it in place)"
  assert_contains "$output" 'SA={"enabled":false,"name":""} ENABLED=false'
  [[ "$output" != *"❌"* ]] || false
}

@test "build_context: tolerant mode disables a service account with an invalid name with a warning" {
  set_scope_config '{"security": {"service_account_enabled": "true", "service_account_name": "My-SA"}}'

  run bash -c 'source "$SCRIPT" && echo "SA=$(echo "$CONTEXT" | jq -c .service_account)"'

  assert_equal "$status" "0"
  assert_contains "$output" "(invalid DNS-1123 name 'My-SA')"
  assert_contains "$output" 'SA={"enabled":false,"name":""}'
}

@test "build_context: tolerant mode still resolves a valid service account and modifiers" {
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"x": "${np.application_slug}"}}}, "security": {"service_account_enabled": "true"}}'

  run bash -c 'source "$SCRIPT" && echo "SA=$(echo "$CONTEXT" | jq -c .service_account) X=$(echo "$CONTEXT" | jq -r .k8s_modifiers.deployment.annotations.x)"'

  assert_equal "$status" "0"
  assert_contains "$output" 'SA={"enabled":true,"name":"test-app-test-scope-123"} X=test-app'
  [[ "$output" != *"Unresolved placeholder"* ]] || false
  [[ "$output" != *"Could not resolve the service account"* ]] || false
}

# =============================================================================
# DNS-1123 subdomain validation of the resolved service account name
# =============================================================================
@test "build_context: service account names with an empty or dash-edged label are rejected" {
  export STRICT_PLACEHOLDERS=true
  for name in "a..b" "a.-b" "a-.b"; do
    set_scope_config "{\"security\": {\"service_account_enabled\": \"true\", \"service_account_name\": \"$name\"}}"
    run bash -c 'source "$SCRIPT"'
    [ "$status" -ne 0 ] || false
    assert_contains "$output" "DNS-1123"
  done
}

@test "build_context: a dotted service account name is accepted" {
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"security": {"service_account_enabled": "true", "service_account_name": "a.b"}}'

  source "$SCRIPT"

  assert_equal "$SERVICE_ACCOUNT_NAME_RESOLVED" "a.b"
}

@test "build_context: a 253-character service account name is accepted and 254 rejected" {
  export STRICT_PLACEHOLDERS=true
  name253="$(printf 'a%.0s' $(seq 1 253))"
  set_scope_config "{\"security\": {\"service_account_enabled\": \"true\", \"service_account_name\": \"$name253\"}}"
  run bash -c 'source "$SCRIPT" && echo "LEN=${#SERVICE_ACCOUNT_NAME_RESOLVED}"'
  assert_equal "$status" "0"
  assert_contains "$output" "LEN=253"

  set_scope_config "{\"security\": {\"service_account_enabled\": \"true\", \"service_account_name\": \"${name253}b\"}}"
  run bash -c 'source "$SCRIPT"'
  [ "$status" -ne 0 ] || false
  assert_contains "$output" "DNS-1123"
}

# =============================================================================
# service_account_enabled / STRICT_PLACEHOLDERS parsing and env fallback
# =============================================================================
@test "build_context: service_account_enabled accepts a JSON boolean true" {
  set_scope_config '{"security": {"service_account_enabled": true}}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -c .service_account)" '{"enabled":true,"name":"test-app-test-scope-123"}'
}

@test "build_context: service_account_enabled is case-insensitive" {
  set_scope_config '{"security": {"service_account_enabled": "TRUE"}}'

  source "$SCRIPT"

  assert_equal "$SERVICE_ACCOUNT_ENABLED" "true"
}

@test "build_context: an invalid service_account_enabled fails in strict mode" {
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"security": {"service_account_enabled": "ture"}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ] || false
  assert_contains "$output" "❌ Invalid security.service_account_enabled value 'ture' (expected true or false)"
}

@test "build_context: an invalid service_account_enabled warns and is treated as false" {
  set_scope_config '{"security": {"service_account_enabled": "yes"}}'

  run bash -c 'source "$SCRIPT" && echo "SA=$(echo "$CONTEXT" | jq -c .service_account)"'

  assert_equal "$status" "0"
  assert_contains "$output" "⚠️  Invalid security.service_account_enabled value 'yes' (expected true or false); treating it as false"
  assert_contains "$output" 'SA={"enabled":false,"name":""}'
}

@test "build_context: SERVICE_ACCOUNT_ENABLED and SERVICE_ACCOUNT_NAME_TEMPLATE env vars are the fallback" {
  export SERVICE_ACCOUNT_ENABLED=true SERVICE_ACCOUNT_NAME_TEMPLATE='env-${np.scope_slug}'

  source "$SCRIPT"

  assert_equal "$(echo "$CONTEXT" | jq -c .service_account)" '{"enabled":true,"name":"env-test-scope"}'
}

@test "build_context: the provider wins over the SERVICE_ACCOUNT_* env vars" {
  export SERVICE_ACCOUNT_ENABLED=true SERVICE_ACCOUNT_NAME_TEMPLATE='env-${np.scope_slug}'
  set_scope_config '{"security": {"service_account_name": "provider-${np.scope_slug}"}}'
  source "$SCRIPT"
  assert_equal "$(echo "$CONTEXT" | jq -r .service_account.name)" "provider-test-scope"

  export SERVICE_ACCOUNT_ENABLED=true
  set_scope_config '{"security": {"service_account_enabled": false}}'
  source "$SCRIPT"
  assert_equal "$(echo "$CONTEXT" | jq -c .service_account)" '{"enabled":false,"name":""}'
}

@test "build_context: STRICT_PLACEHOLDERS is case-insensitive" {
  export STRICT_PLACEHOLDERS=TRUE
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"x": "${np.nope}"}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ] || false
  assert_contains "$output" "np.nope"
}

@test "build_context: an invalid STRICT_PLACEHOLDERS fails" {
  export STRICT_PLACEHOLDERS=yes

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ] || false
  assert_contains "$output" "❌ Invalid STRICT_PLACEHOLDERS value 'yes' (expected true or false)"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# IAM and the per-scope service account are mutually exclusive
# =============================================================================
@test "build_context: IAM and service_account_enabled together fail before any step in strict mode" {
  export STRICT_PLACEHOLDERS=true IAM='{"ENABLED":true,"PREFIX":"np-role"}'
  set_scope_config '{"security": {"service_account_enabled": "true"}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ] || false
  assert_contains "$output" "❌ IAM and service_account_enabled are both enabled for this scope"
  assert_contains "$output" "• Disable security.iam_enabled or security.service_account_enabled in scope-configurations"
  [[ "$output" != *"Scope context built successfully"* ]] || false
}

@test "build_context: IAM and service_account_enabled together warn and ignore the per-scope SA outside strict mode" {
  export IAM='{"ENABLED":"true","PREFIX":"np-role"}'
  set_scope_config '{"security": {"service_account_enabled": "true"}}'

  run bash -c 'source "$SCRIPT" && echo "SA=$(echo "$CONTEXT" | jq -c .service_account) ENABLED=$SERVICE_ACCOUNT_ENABLED"'

  assert_equal "$status" "0"
  assert_contains "$output" "⚠️  IAM and service_account_enabled are both enabled; the per-scope service account is ignored because IAM owns the pod service account"
  assert_contains "$output" 'SA={"enabled":false,"name":""} ENABLED=false'
}

@test "build_context: IAM disabled keeps the per-scope service account in strict mode" {
  export STRICT_PLACEHOLDERS=true IAM='{"ENABLED":false}'
  set_scope_config '{"security": {"service_account_enabled": "true"}}'

  source "$SCRIPT"

  assert_equal "$SERVICE_ACCOUNT_ENABLED" "true"
}

# =============================================================================
# Placeholder helper failures follow the strict / tolerant mode explicitly
# =============================================================================
failing_helpers() {
  source "$PROJECT_ROOT/k8s/utils/expand_placeholders"
  export _NP_PLACEHOLDER_JQ_DEFS
  export -f _np_placeholder_jq drop_placeholder_entries
  expand_placeholders() { log error "   ❌ helper failed"; return 1; }
  unresolved_placeholders() { log error "   ❌ helper failed"; return 1; }
  expand_resolvable_placeholders() { log error "   ❌ helper failed"; return 1; }
  unresolved_placeholder_paths() { log error "   ❌ helper failed"; return 1; }
  expand_placeholder_string() { log error "   ❌ helper failed"; return 1; }
  export -f expand_placeholders unresolved_placeholders expand_resolvable_placeholders unresolved_placeholder_paths expand_placeholder_string
}

@test "build_context: a placeholder helper failure exits in strict mode" {
  failing_helpers
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"object_modifiers": {"deployment": {"annotations": {"x": "${np.application_slug}"}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ] || false
  assert_contains "$output" "helper failed"
}

@test "build_context: a placeholder helper failure drops only the entries holding placeholders in tolerant mode" {
  failing_helpers
  set_scope_config '{"object_modifiers": {"ingress": {"annotations": {"x": "${np.application_slug}", "keep": "v"}}}, "security": {"service_account_enabled": "true"}}'

  run bash -c 'source "$SCRIPT" && echo "MODS=$(echo "$CONTEXT" | jq -c .k8s_modifiers) SA=$(echo "$CONTEXT" | jq -c .service_account)"'

  assert_equal "$status" "0"
  assert_contains "$output" "⚠️  Could not evaluate placeholders in object_modifiers; dropping every entry that holds one for this action"
  assert_contains "$output" 'MODS={"ingress":{"annotations":{"keep":"v"}}} SA={"enabled":false,"name":""}'
}

@test "build_context: modifiers are ignored in tolerant mode when not even the fallback can read them" {
  failing_helpers
  drop_placeholder_entries() { log error "   ❌ helper failed"; return 1; }
  export -f drop_placeholder_entries
  set_scope_config '{"object_modifiers": {"ingress": {"annotations": {"x": "${np.application_slug}"}}}}'

  run bash -c 'source "$SCRIPT" && echo "MODS=$(echo "$CONTEXT" | jq -c .k8s_modifiers)"'

  assert_equal "$status" "0"
  assert_contains "$output" "⚠️  Could not drop the object_modifiers entries holding placeholders; ignoring object_modifiers for this action"
  assert_contains "$output" 'MODS={}'
}

@test "build_context: modifiers without placeholders never call the placeholder helpers" {
  failing_helpers
  export STRICT_PLACEHOLDERS=true
  set_scope_config '{"object_modifiers": {"deployment": {"labels": {"a": "b"}}}}'

  run bash -c 'source "$SCRIPT" && echo "MODS=$(echo "$CONTEXT" | jq -c .k8s_modifiers)"'

  assert_equal "$status" "0"
  assert_contains "$output" 'MODS={"deployment":{"labels":{"a":"b"}}}'
}
