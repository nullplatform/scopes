# Kubernetes Scope Configuration

This document describes all available configuration variables for Kubernetes scopes, their priority hierarchy, and how to configure them.

## Configuration Hierarchy

Configuration variables follow a priority hierarchy:

```
1. Existing Providers - Highest priority
   - scope-configuration: Scope-specific configuration
   - container-orchestration: Orchestrator configuration
   - cloud-providers: Cloud provider configuration
   (If there are multiple providers, the order in which they are specified determines priority)
   ↓
2. Environment Variable (ENV VAR) - Allows override when no provider exists
   ↓
3. values.yaml - Default values for the scope type
```

**Important Note**: The order of arguments in `get_config_value` does NOT affect priority. The function always respects the order: providers > env var > default, regardless of the order in which arguments are passed.

## Configuration Variables

### Scope Context (`k8s/scope/build_context`)

Variables that define the general context of the scope and Kubernetes resources.

| Variable | Description | values.yaml | scope-configuration (JSON Schema) | Files Using It | Default |
|----------|-------------|-------------|-----------------------------------|----------------|---------|
| **K8S_NAMESPACE** | Kubernetes namespace where resources are deployed | `configuration.K8S_NAMESPACE` | `kubernetes.namespace` | `k8s/scope/build_context`<br>`k8s/deployment/build_context` | `"nullplatform"` |
| **CREATE_K8S_NAMESPACE_IF_NOT_EXIST** | Whether to create the namespace if it doesn't exist | `configuration.CREATE_K8S_NAMESPACE_IF_NOT_EXIST` | `kubernetes.create_namespace_if_not_exist` | `k8s/scope/build_context` | `"true"` |
| **K8S_MODIFIERS** | Modifiers (annotations, labels, tolerations) for K8s resources | `configuration.K8S_MODIFIERS` | `kubernetes.modifiers` | `k8s/scope/build_context` | `{}` |
| **REGION** | AWS/Cloud region where resources are deployed. **Note:** Only obtained from `cloud-providers` provider, not from `scope-configuration` | N/A (cloud-providers only) | N/A | `k8s/scope/build_context` | `"us-east-1"` |
| **USE_ACCOUNT_SLUG** | Whether to use account slug as application domain | `configuration.USE_ACCOUNT_SLUG` | `networking.application_domain` | `k8s/scope/build_context` | `"false"` |
| **DOMAIN** | Public domain for the application | `configuration.DOMAIN` | `networking.domain_name` | `k8s/scope/build_context` | `"nullapps.io"` |
| **PRIVATE_DOMAIN** | Private domain for internal services | `configuration.PRIVATE_DOMAIN` | `networking.private_domain_name` | `k8s/scope/build_context` | `"nullapps.io"` |
| **PUBLIC_GATEWAY_NAME** | Public gateway name for ingress | Env var or default | `gateway.public_name` | `k8s/scope/build_context` | `"gateway-public"` |
| **PRIVATE_GATEWAY_NAME** | Private/internal gateway name for ingress | Env var or default | `gateway.private_name` | `k8s/scope/build_context` | `"gateway-internal"` |
| **ALB_NAME** (public) | Public Application Load Balancer name | Calculated | `balancer.public_name` | `k8s/scope/build_context` | `"k8s-nullplatform-internet-facing"` |
| **ALB_NAME** (private) | Private Application Load Balancer name | Calculated | `balancer.private_name` | `k8s/scope/build_context` | `"k8s-nullplatform-internal"` |
| **DNS_TYPE** | DNS provider type (route53, azure, external_dns) | `configuration.DNS_TYPE` | `dns.type` | `k8s/scope/build_context`<br>DNS Workflows | `"route53"` |
| **ALB_RECONCILIATION_ENABLED** | Whether ALB reconciliation is enabled | `configuration.ALB_RECONCILIATION_ENABLED` | `networking.alb_reconciliation_enabled` | `k8s/scope/build_context`<br>Balancer Workflows | `"false"` |
| **DEPLOYMENT_MAX_WAIT_IN_SECONDS** | Maximum wait time for deployments (seconds) | `configuration.DEPLOYMENT_MAX_WAIT_IN_SECONDS` | `deployment.max_wait_seconds` | `k8s/scope/build_context`<br>Deployment Workflows | `600` |
| **MANIFEST_BACKUP** | K8s manifests backup configuration | `configuration.MANIFEST_BACKUP` | `manifest_backup` | `k8s/scope/build_context`<br>Backup Workflows | `{}` |
| **VAULT_ADDR** | Vault server URL for secrets | `configuration.VAULT_ADDR` | `vault.address` | `k8s/scope/build_context`<br>Secrets Workflows | `""` (empty) |
| **VAULT_TOKEN** | Vault authentication token | `configuration.VAULT_TOKEN` | `vault.token` | `k8s/scope/build_context`<br>Secrets Workflows | `""` (empty) |

### Deployment Context (`k8s/deployment/build_context`)

Deployment-specific variables and pod configuration.

| Variable | Description | values.yaml | scope-configuration (JSON Schema) | Files Using It | Default |
|----------|-------------|-------------|-----------------------------------|----------------|---------|
| **IMAGE_PULL_SECRETS** | Secrets for pulling images from private registries | `configuration.IMAGE_PULL_SECRETS` | `deployment.image_pull_secrets` | `k8s/deployment/build_context` | `{}` |
| **TRAFFIC_CONTAINER_IMAGE** | Traffic manager sidecar container image | `configuration.TRAFFIC_CONTAINER_IMAGE` | `deployment.traffic_container_image` | `k8s/deployment/build_context` | `"public.ecr.aws/nullplatform/k8s-traffic-manager:latest"` |
| **POD_DISRUPTION_BUDGET_ENABLED** | Whether Pod Disruption Budget is enabled | `configuration.POD_DISRUPTION_BUDGET.ENABLED` | `deployment.pod_disruption_budget.enabled` | `k8s/deployment/build_context` | `"false"` |
| **POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE** | Maximum number or percentage of pods that can be unavailable | `configuration.POD_DISRUPTION_BUDGET.MAX_UNAVAILABLE` | `deployment.pod_disruption_budget.max_unavailable` | `k8s/deployment/build_context` | `"25%"` |
| **TRAFFIC_MANAGER_CONFIG_MAP** | ConfigMap name with custom traffic manager configuration | `configuration.TRAFFIC_MANAGER_CONFIG_MAP` | `deployment.traffic_manager_config_map` | `k8s/deployment/build_context` | `""` (empty) |
| **DEPLOY_STRATEGY** | Deployment strategy (rolling or blue-green) | `configuration.DEPLOY_STRATEGY` | `deployment.strategy` | `k8s/deployment/build_context`<br>`k8s/deployment/scale_deployments` | `"rolling"` |
| **IAM** | IAM roles and policies configuration for service accounts | `configuration.IAM` | `deployment.iam` | `k8s/deployment/build_context`<br>`k8s/scope/iam/*` | `{}` |

## Configuration via scope-configuration Provider

### Complete JSON Structure

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "production",
      "create_namespace_if_not_exist": "true",
      "modifiers": {
        "global": {
          "annotations": {
            "prometheus.io/scrape": "true"
          },
          "labels": {
            "environment": "production"
          }
        },
        "deployment": {
          "tolerations": [
            {
              "key": "dedicated",
              "operator": "Equal",
              "value": "production",
              "effect": "NoSchedule"
            }
          ]
        }
      }
    },
    "networking": {
      "domain_name": "example.com",
      "private_domain_name": "internal.example.com",
      "application_domain": "false"
    },
    "gateway": {
      "public_name": "my-public-gateway",
      "private_name": "my-private-gateway"
    },
    "balancer": {
      "public_name": "my-public-alb",
      "private_name": "my-private-alb"
    },
    "dns": {
      "type": "route53"
    },
    "networking": {
      "alb_reconciliation_enabled": "false"
    },
    "deployment": {
      "image_pull_secrets": {
        "ENABLED": true,
        "SECRETS": ["ecr-secret", "dockerhub-secret"]
      },
      "traffic_container_image": "custom.ecr.aws/traffic-manager:v2.0",
      "pod_disruption_budget": {
        "enabled": "true",
        "max_unavailable": "1"
      },
      "traffic_manager_config_map": "custom-nginx-config",
      "strategy": "blue-green",
      "max_wait_seconds": 600,
      "iam": {
        "ENABLED": true,
        "PREFIX": "my-app-scopes",
        "ROLE": {
          "POLICIES": [
            {
              "TYPE": "arn",
              "VALUE": "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
            }
          ]
        }
      }
    },
    "manifest_backup": {
      "ENABLED": false,
      "TYPE": "s3",
      "BUCKET": "my-backup-bucket",
      "PREFIX": "k8s-manifests"
    },
    "vault": {
      "address": "https://vault.example.com",
      "token": "s.xxxxxxxxxxxxx"
    }
  }
}
```

### Configuración Mínima

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "staging"
    }
  }
}
```

**Note**: The region (`REGION`) is automatically obtained from the `cloud-providers` provider, it is not configured in `scope-configuration`.

## Environment Variables

Environment variables allow configuring values when they are not defined in providers. Note that providers have higher priority than environment variables:

```bash
# Kubernetes
export NAMESPACE_OVERRIDE="my-custom-namespace"
export CREATE_K8S_NAMESPACE_IF_NOT_EXIST="false"
export K8S_MODIFIERS='{"global":{"labels":{"team":"platform"}}}'

# DNS & Networking
export DNS_TYPE="azure"
export ALB_RECONCILIATION_ENABLED="true"

# Deployment
export IMAGE_PULL_SECRETS='{"ENABLED":true,"SECRETS":["my-secret"]}'
export TRAFFIC_CONTAINER_IMAGE="custom.ecr.aws/traffic:v1.0"
export POD_DISRUPTION_BUDGET_ENABLED="true"
export POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE="2"
export TRAFFIC_MANAGER_CONFIG_MAP="my-config-map"
export DEPLOY_STRATEGY="blue-green"
export DEPLOYMENT_MAX_WAIT_IN_SECONDS="900"
export IAM='{"ENABLED":true,"PREFIX":"my-app"}'

# Manifest Backup
export MANIFEST_BACKUP='{"ENABLED":true,"TYPE":"s3","BUCKET":"my-backups","PREFIX":"manifests/"}'

# Vault Integration
export VAULT_ADDR="https://vault.mycompany.com"
export VAULT_TOKEN="s.abc123xyz789"

# Gateway & Balancer
export PUBLIC_GATEWAY_NAME="gateway-prod"
export PRIVATE_GATEWAY_NAME="gateway-internal-prod"
```

## Additional Variables (values.yaml Only)

The following variables are defined in `k8s/values.yaml` but are **not yet integrated** with the scope-configuration hierarchy system. They can only be configured via `values.yaml`:

| Variable | Description | values.yaml | Default | Files Using It |
|----------|-------------|-------------|---------|----------------|
| **DEPLOYMENT_TEMPLATE** | Path to deployment template | `configuration.DEPLOYMENT_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/deployment.yaml.tpl"` | Deployment workflows |
| **SECRET_TEMPLATE** | Path to secrets template | `configuration.SECRET_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/secret.yaml.tpl"` | Deployment workflows |
| **SCALING_TEMPLATE** | Path to scaling/HPA template | `configuration.SCALING_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/scaling.yaml.tpl"` | Scaling workflows |
| **SERVICE_TEMPLATE** | Path to service template | `configuration.SERVICE_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/service.yaml.tpl"` | Deployment workflows |
| **PDB_TEMPLATE** | Path to Pod Disruption Budget template | `configuration.PDB_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/pdb.yaml.tpl"` | Deployment workflows |
| **INITIAL_INGRESS_PATH** | Path to initial ingress template | `configuration.INITIAL_INGRESS_PATH` | `"$SERVICE_PATH/deployment/templates/initial-ingress.yaml.tpl"` | Ingress workflows |
| **BLUE_GREEN_INGRESS_PATH** | Path to blue-green ingress template | `configuration.BLUE_GREEN_INGRESS_PATH` | `"$SERVICE_PATH/deployment/templates/blue-green-ingress.yaml.tpl"` | Ingress workflows |
| **SERVICE_ACCOUNT_TEMPLATE** | Path to service account template | `configuration.SERVICE_ACCOUNT_TEMPLATE` | `"$SERVICE_PATH/scope/templates/service-account.yaml.tpl"` | IAM workflows |

> **Note**: These variables are template paths and are pending migration to the scope-configuration hierarchy system. Currently they can only be configured in `values.yaml` or via environment variables without provider support.

### IAM Configuration

```yaml
IAM:
  ENABLED: false
  PREFIX: nullplatform-scopes
  ROLE:
    POLICIES:
      - TYPE: arn
        VALUE: arn:aws:iam::aws:policy/AmazonS3FullAccess
      - TYPE: inline
        VALUE: |
          {
            "Version": "2012-10-17",
            "Statement": [...]
          }
    BOUNDARY_ARN: arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### Manifest Backup Configuration

```yaml
MANIFEST_BACKUP:
  ENABLED: false
  TYPE: s3
  BUCKET: my-backup-bucket
  PREFIX: k8s-manifests
```

## Important Variables Details

### K8S_MODIFIERS

Allows adding annotations, labels and tolerations to Kubernetes resources. Structure:

```json
{
  "global": {
    "annotations": { "key": "value" },
    "labels": { "key": "value" }
  },
  "service": {
    "annotations": { "service.beta.kubernetes.io/aws-load-balancer-type": "nlb" }
  },
  "ingress": {
    "annotations": { "alb.ingress.kubernetes.io/scheme": "internet-facing" }
  },
  "deployment": {
    "annotations": { "prometheus.io/scrape": "true" },
    "labels": { "app-tier": "backend" },
    "tolerations": [
      {
        "key": "dedicated",
        "operator": "Equal",
        "value": "production",
        "effect": "NoSchedule"
      }
    ]
  },
  "secret": {
    "labels": { "encrypted": "true" }
  }
}
```

### IMAGE_PULL_SECRETS

Configuration for pulling images from private registries:

```json
{
  "ENABLED": true,
  "SECRETS": [
    "ecr-secret",
    "dockerhub-secret"
  ]
}
```

### POD_DISRUPTION_BUDGET

Ensures high availability during updates. `max_unavailable` can be:
- **Percentage**: `"25%"` - maximum 25% of pods unavailable
- **Absolute number**: `"1"` - maximum 1 pod unavailable

### DEPLOY_STRATEGY

Deployment strategy to use:
- **`rolling`** (default): Progressive deployment, new pods gradually replace old ones
- **`blue-green`**: Side-by-side deployment, instant traffic switch between versions

### IAM

Configuration for AWS IAM integration. Allows assigning IAM roles to Kubernetes service accounts:

```json
{
  "ENABLED": true,
  "PREFIX": "my-app-scopes",
  "ROLE": {
    "POLICIES": [
      {
        "TYPE": "arn",
        "VALUE": "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
      },
      {
        "TYPE": "inline",
        "VALUE": "{\"Version\":\"2012-10-17\",\"Statement\":[...]}"
      }
    ],
    "BOUNDARY_ARN": "arn:aws:iam::aws:policy/PowerUserAccess"
  }
}
```

When enabled, creates a service account with name `{PREFIX}-{SCOPE_ID}` and associates it with the configured IAM role.

### DNS_TYPE

Specifies the DNS provider type for managing DNS records:

- **`route53`** (default): Amazon Route53
- **`azure`**: Azure DNS
- **`external_dns`**: External DNS for integration with other providers

```json
{
  "dns": {
    "type": "route53"
  }
}
```

### MANIFEST_BACKUP

Configuration for automatic backups of applied Kubernetes manifests:

```json
{
  "manifest_backup": {
    "ENABLED": true,
    "TYPE": "s3",
    "BUCKET": "my-k8s-backups",
    "PREFIX": "prod/manifests"
  }
}
```

Properties:
- **`ENABLED`**: Enables or disables backup (boolean)
- **`TYPE`**: Storage type for backups (currently only `"s3"`)
- **`BUCKET`**: S3 bucket name where backups are stored
- **`PREFIX`**: Prefix/path within the bucket to organize manifests

### VAULT Integration

Integration with HashiCorp Vault for secrets management:

```json
{
  "vault": {
    "address": "https://vault.example.com",
    "token": "s.xxxxxxxxxxxxx"
  }
}
```

Properties:
- **`address`**: Complete Vault server URL (must include https:// protocol)
- **`token`**: Authentication token to access Vault

When configured, the system can obtain secrets from Vault instead of using native Kubernetes Secrets.

> **Security Note**: Never commit the Vault token in code. Use environment variables or secret management systems to inject the token at runtime.

### DEPLOYMENT_MAX_WAIT_IN_SECONDS

Maximum time (in seconds) the system will wait for a deployment to become ready before considering it failed:

- **Default**: `600` (10 minutes)
- **Recommended values**:
  - Lightweight applications: `300` (5 minutes)
  - Heavy applications or slow initialization: `900` (15 minutes)
  - Applications with complex migrations: `1200` (20 minutes)

```json
{
  "deployment": {
    "max_wait_seconds": 600
  }
}
```

### ALB_RECONCILIATION_ENABLED

Enables automatic reconciliation of Application Load Balancers. When enabled, the system verifies and updates the ALB configuration to keep it synchronized with the desired configuration:

- **`"true"`**: Reconciliation enabled
- **`"false"`** (default): Reconciliation disabled

```json
{
  "networking": {
    "alb_reconciliation_enabled": "true"
  }
}
```

### TRAFFIC_MANAGER_CONFIG_MAP

If specified, must be an existing ConfigMap with:
- `nginx.conf` - Main nginx configuration
- `default.conf` - Virtual host configuration

## Configuration Validation

The JSON Schema is available at `/scope-configuration.schema.json` in the project root.

To validate your configuration:

```bash
# Using ajv-cli
ajv validate -s scope-configuration.schema.json -d your-config.json

# Using jq (basic validation)
jq empty your-config.json && echo "Valid JSON"
```

## Usage Examples

### Local Development

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "dev-local",
      "create_namespace_if_not_exist": "true"
    },
    "networking": {
      "domain_name": "dev.local"
    }
  }
}
```

### Production with High Availability

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "production",
      "modifiers": {
        "deployment": {
          "tolerations": [
            {
              "key": "dedicated",
              "operator": "Equal",
              "value": "production",
              "effect": "NoSchedule"
            }
          ]
        }
      }
    },
    "deployment": {
      "pod_disruption_budget": {
        "enabled": "true",
        "max_unavailable": "1"
      }
    }
  }
}
```

### Multiple Registries

```json
{
  "scope-configuration": {
    "deployment": {
      "image_pull_secrets": {
        "ENABLED": true,
        "SECRETS": [
          "ecr-secret",
          "dockerhub-secret",
          "gcr-secret"
        ]
      }
    }
  }
}
```

### Vault Integration and Backups

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "production"
    },
    "vault": {
      "address": "https://vault.company.com",
      "token": "s.abc123xyz"
    },
    "manifest_backup": {
      "ENABLED": true,
      "TYPE": "s3",
      "BUCKET": "prod-k8s-backups",
      "PREFIX": "scope-manifests/"
    },
    "deployment": {
      "max_wait_seconds": 900
    }
  }
}
```

### Custom DNS with Azure

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "staging"
    },
    "dns": {
      "type": "azure"
    },
    "networking": {
      "domain_name": "staging.example.com",
      "alb_reconciliation_enabled": "true"
    }
  }
}
```

## Tests

Configurations are fully tested with BATS:

```bash
# Run all tests
make test-unit MODULE=k8s

# Specific tests
./testing/run_bats_tests.sh k8s/utils/tests        # get_config_value tests
./testing/run_bats_tests.sh k8s/scope/tests        # scope/build_context tests
./testing/run_bats_tests.sh k8s/deployment/tests   # deployment/build_context tests
```

**Total: 75 tests covering all variables and configuration hierarchies** ✅
- 19 tests in `k8s/utils/tests/get_config_value.bats`
- 27 tests in `k8s/scope/tests/build_context.bats`
- 29 tests in `k8s/deployment/tests/build_context.bats`

## Related Files

- **Utility function**: `k8s/utils/get_config_value` - Implements the configuration hierarchy
- **Build contexts**:
  - `k8s/scope/build_context` - Scope context
  - `k8s/deployment/build_context` - Deployment context
- **Schema**: `/scope-configuration.schema.json` - Complete JSON Schema
- **Defaults**: `k8s/values.yaml` - Default values for the scope type
- **Tests**:
  - `k8s/utils/tests/get_config_value.bats`
  - `k8s/scope/tests/build_context.bats`
  - `k8s/deployment/tests/build_context.bats`

## Contributing

When adding new configuration variables:

1. Update `k8s/scope/build_context` or `k8s/deployment/build_context` using `get_config_value`
2. Add the property in `scope-configuration.schema.json`
3. Document the default in `k8s/values.yaml` if applicable
4. Create tests in the corresponding `.bats` file
5. Update this README
