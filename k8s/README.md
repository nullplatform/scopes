# Kubernetes Scope Configuration

This document describes all available configuration variables for Kubernetes scopes and their priority hierarchy.

## Configuration Hierarchy

Configuration variables follow a priority hierarchy:

```
1. Existing Providers - Highest priority
   - scope-configurations: Scope-specific configuration
   - container-orchestration: Orchestrator configuration
   - cloud-providers: Cloud provider configuration
   (If there are multiple providers, the order in which they are specified determines priority)
   ↓
2. Environment Variable (ENV VAR) - Allows override when no provider exists
   ↓
3. Default value - Fallback when no provider or env var exists
```

**Important Note**: The order of arguments in `get_config_value` does NOT affect priority. The function always respects the order: providers > env var > default, regardless of the order in which arguments are passed.

## Configuration Variables

### Cluster

Configuration for Kubernetes cluster settings.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **K8S_NAMESPACE** | Kubernetes namespace where resources are deployed | `cluster.namespace` |
| **CREATE_K8S_NAMESPACE_IF_NOT_EXIST** | Whether to create the namespace if it doesn't exist | `cluster.create_namespace_if_not_exist` |

### Networking

#### General

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **DOMAIN** | Public domain name for the application | `networking.domain_name` |
| **PRIVATE_DOMAIN** | Private domain name for internal services | `networking.private_domain_name` |
| **USE_ACCOUNT_SLUG** | Whether to use account slug as application domain | `networking.application_domain` |
| **DNS_TYPE** | DNS provider type (route53, azure, external_dns) | `networking.dns_type` |

#### AWS Route53

Configuration specific to AWS Route53 DNS provider. Visible only when `dns_type` is `route53`.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **ALB_NAME** (public) | Public Application Load Balancer name | `networking.balancer_public_name` |
| **ALB_NAME** (private) | Private Application Load Balancer name | `networking.balancer_private_name` |
| **ALB_RECONCILIATION_ENABLED** | Whether ALB reconciliation is enabled | `networking.alb_reconciliation_enabled` |

#### Azure DNS

Configuration specific to Azure DNS provider. Visible only when `dns_type` is `azure`.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **HOSTED_ZONE_NAME** | Azure DNS hosted zone name | `networking.hosted_zone_name` |
| **HOSTED_ZONE_RG** | Azure resource group containing the DNS hosted zone | `networking.hosted_zone_rg` |
| **AZURE_SUBSCRIPTION_ID** | Azure subscription ID for DNS management | `networking.azure_subscription_id` |
| **RESOURCE_GROUP** | Azure resource group for cluster resources | `networking.resource_group` |

#### Gateways

Gateway configuration for ingress traffic routing.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **PUBLIC_GATEWAY_NAME** | Public gateway name for ingress | `networking.gateway_public_name` |
| **PRIVATE_GATEWAY_NAME** | Private/internal gateway name for ingress | `networking.gateway_private_name` |

### Deployment

#### General

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **DEPLOY_STRATEGY** | Deployment strategy (rolling or blue-green) | `deployment.deployment_strategy` |
| **DEPLOYMENT_MAX_WAIT_IN_SECONDS** | Maximum wait time for deployments (seconds) | `deployment.deployment_max_wait_seconds` |

#### Traffic Manager

Configuration for the traffic manager sidecar container.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **TRAFFIC_CONTAINER_IMAGE** | Traffic manager sidecar container image | `deployment.traffic_container_image` |
| **TRAFFIC_MANAGER_CONFIG_MAP** | ConfigMap name with custom traffic manager configuration | `deployment.traffic_manager_config_map` |

#### Pod Disruption Budget

Configuration for Pod Disruption Budget to control pod availability during disruptions.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **POD_DISRUPTION_BUDGET_ENABLED** | Whether Pod Disruption Budget is enabled | `deployment.pod_disruption_budget_enabled` |
| **POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE** | Maximum number or percentage of pods that can be unavailable | `deployment.pod_disruption_budget_max_unavailable` |

#### Manifest Backup

Configuration for backing up Kubernetes manifests.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **MANIFEST_BACKUP_ENABLED** | Whether manifest backup is enabled | `deployment.manifest_backup_enabled` |
| **MANIFEST_BACKUP_TYPE** | Backup storage type | `deployment.manifest_backup_type` |
| **MANIFEST_BACKUP_BUCKET** | S3 bucket name for storing backups | `deployment.manifest_backup_bucket` |
| **MANIFEST_BACKUP_PREFIX** | Prefix path within the bucket | `deployment.manifest_backup_prefix` |

### Security

#### Image Pull Secrets

Configuration for pulling images from private container registries.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **IMAGE_PULL_SECRETS_ENABLED** | Whether image pull secrets are enabled | `security.image_pull_secrets_enabled` |
| **IMAGE_PULL_SECRETS** | List of secret names to use for pulling images | `security.image_pull_secrets` |

#### IAM

AWS IAM configuration for Kubernetes service accounts.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **IAM_ENABLED** | Whether IAM integration is enabled | `security.iam_enabled` |
| **IAM_PREFIX** | Prefix for IAM role names | `security.iam_prefix` |
| **IAM_POLICIES** | List of IAM policies to attach to the role | `security.iam_policies` |
| **IAM_BOUNDARY_ARN** | ARN of the permissions boundary policy | `security.iam_boundary_arn` |

#### Vault

HashiCorp Vault configuration for secrets management.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **VAULT_ADDR** | Vault server address | `security.vault_address` |
| **VAULT_TOKEN** | Vault authentication token | `security.vault_token` |

### Advanced

Advanced configuration options.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **K8S_MODIFIERS** | JSON string with dynamic modifications to Kubernetes objects | `object_modifiers` |
