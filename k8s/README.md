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

A provider only falls through when its value is missing or `null`. A boolean `false` is a value: it wins over later providers, env vars and the default.

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

**Note:** These variables are obtained from the `scope-configurations` provider and exported for use in Azure DNS workflows.

#### Gateways

Gateway configuration for ingress traffic routing.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **PUBLIC_GATEWAY_NAME** | Public gateway name for ingress | `networking.gateway_public_name` |
| **PRIVATE_GATEWAY_NAME** | Private/internal gateway name for ingress | `networking.gateway_private_name` |
| **GATEWAY_EXTERNAL_IP** | Address published in DNS instead of the one detected from the cluster. Set it when a NAT/VIP device fronts the gateway, so records carry the externally reachable address rather than the internal one. An IPv4 value yields an A record, a hostname a CNAME. | _environment variable_ |

**Note:** `GATEWAY_EXTERNAL_IP` is read straight from the agent's environment, not from the
`scope-configurations` provider, and only applies to the `external_dns` DNS type. Left unset,
the address is auto-detected from the Gateway or its Service, which is correct whenever no
address translation sits in front of the cluster.

### Deployment

#### General

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **DEPLOY_STRATEGY** | Deployment strategy (rolling or blue-green) | `deployment.deployment_strategy` |
| **DEPLOYMENT_MAX_WAIT_IN_SECONDS** | Maximum wait time for deployments (seconds) | `deployment.deployment_max_wait_seconds` |
| **KUBECTL_DELETE_TIMEOUT_SECONDS** | Maximum time a `kubectl delete` waits for the objects to be gone, finalizers included (seconds, default `300`). When it runs out, the deletion is logged as failed instead of hanging the workflow | - |

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

#### Assuming an IAM role for AWS operations

By default the scope's AWS CLI calls (IAM, ELBv2, Route53, S3, CloudWatch) use
the agent's own credentials. To run them under a dedicated IAM role per account,
configure the nullplatform **AWS IAM provider** (`aws-iam-configuration`) with an
`iam_role_arns.arns` entry whose `selector` is `containers`:

```hcl
attributes = {
  iam_role_arns = {
    arns = [
      { selector = "containers", arn = "arn:aws:iam::<account>:role/<role>" }
    ]
  }
}
```

Resolution precedence (first non-empty wins):

1. `CONTAINERS_ASSUME_ROLE_ARN` environment variable (explicit override).
2. AWS IAM provider entry matching the selector (`CONTAINERS_ASSUME_ROLE_SELECTOR`, default `containers`).
3. `CONTAINERS_ASSUME_ROLE_ARN_DEFAULT` environment variable.
4. None configured → the agent's credentials are used (no role assumed).

The IAM provider is resolved **for the scope's dimensions** by the platform: it
is read from `CONTEXT.providers["identity-access-control"]`, which the engine
populates with the most-specific provider config whose `dimensions` are a subset
of the scope's dimensions (the empty-dimension config is the default). The
selector is then matched within that already-resolved config. For this to work,
`identity-access-control` must be listed under `provider_categories` in
`values.yaml`. This lets different dimensions map to different assumable roles
using the same matching the rest of the platform uses.

The target role's trust policy must allow the agent's role to call
`sts:AssumeRole`.

This step runs only on EKS (`K8S_FLAVOR` = `eks` or unset); on other flavors
(AKS, ARO) it is skipped and `CONTAINERS_ASSUME_ROLE_ARN` is ignored.

#### Using an Azure managed identity for Azure operations (AKS)

On AKS (`K8S_FLAVOR=aks`), the scope's Azure calls (Azure DNS records) use the
agent's Service Principal credentials by default. To run them as a dedicated
managed identity per dimension instead, with no client secret, configure the
nullplatform **Azure identity provider** (`azure-identity-configuration`) with a
`managed_identities.identities` entry whose `selector` is `containers`:

```hcl
attributes = {
  managed_identities = {
    identities = [
      { selector = "containers", client_id = "<managed identity client id>" }
    ]
  }
}
```

Resolution precedence (first non-empty wins):

1. `CONTAINERS_AZURE_CLIENT_ID` environment variable (explicit override).
2. Azure identity provider entry matching the selector (`CONTAINERS_AZURE_IDENTITY_SELECTOR`, default `containers`).
3. `CONTAINERS_AZURE_CLIENT_ID_DEFAULT` environment variable.
4. None configured → the agent's credentials are used.

Until the `azure-identity-configuration` provider type is available in Platform
Settings, the environment variables (`CONTAINERS_AZURE_CLIENT_ID`,
`CONTAINERS_AZURE_CLIENT_ID_DEFAULT`) are the way to configure this.

> **Warning:** once the Service Principal client secret is removed from the
> agent, every dimension needs a resolved identity (a provider entry or
> `CONTAINERS_AZURE_CLIENT_ID_DEFAULT`) — otherwise Azure DNS calls for that
> dimension have no credentials to use.

The provider is resolved for the scope's dimensions exactly like the AWS IAM
provider above. When an identity is resolved, the `azure identity` workflow step
exports `AZURE_CLIENT_ID`, clears `AZURE_CLIENT_SECRET` and performs one token
exchange to verify the setup before any Azure resource is touched.

Requirements:

- The agent and its worker pods carry the label `azure.workload.identity/use: "true"`
  (`azure_workload_identity = true` on the `nullplatform/agent` tofu module).
- The managed identity has a federated identity credential trusting the cluster's
  OIDC issuer and the subject `system:serviceaccount:<agent namespace>:<agent service account>`.
- The managed identity holds the roles the scope needs (e.g. `DNS Zone Contributor`
  on the DNS zone).

#### Service Account

Runs the scope's pods with a dedicated Kubernetes ServiceAccount, without AWS IAM. Useful when workloads
authenticate to the cluster identity (e.g. Vault Kubernetes auth) and each application needs its own identity.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **SERVICE_ACCOUNT_ENABLED** | Whether the scope runs with its own ServiceAccount (default `false`) | `security.service_account_enabled` |
| **SERVICE_ACCOUNT_NAME_TEMPLATE** | Name of the ServiceAccount, accepts [placeholders](#placeholders) (default `${np.application_slug}-${np.scope_id}`) | `security.service_account_name` |

- The resolved name must be a valid DNS-1123 subdomain (lowercase alphanumerics, `-` or `.`, at most 253 characters); otherwise scope create/update and deployments fail (see [placeholders](#placeholders) for other actions).
- It is mutually exclusive with `security.iam_enabled`: enabling both fails scope create/update and deployments, because both define the pod service account. Rollback, switch traffic, finalize and deletes only warn and keep the IAM service account, so enabling both never blocks them.
- **Ownership.** The scope manages a ServiceAccount only if it carries the label `scope_id` equal to the scope's id.
  - Labeled with another scope's id: scope create/update and deployments fail, naming the owning scope.
  - Without the `scope_id` label: it is used as-is, with a warning, and is never modified or deleted. This lets you bring your own ServiceAccount by pre-creating it.
- Include `${np.scope_id}` (or another part unique per scope) in the name, unless several scopes deliberately share a pre-created, unlabeled ServiceAccount.
- The agent reads the ServiceAccount before creating or deleting it, so it needs `get` on `serviceaccounts` in the scope namespace (the agent chart's default ClusterRole grants it).
- **Limitations.** Changing the name template or disabling the feature does not remove the ServiceAccount created earlier; it stays in the cluster as an orphan until removed manually or through your IaC.

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
| **K8S_MODIFIERS** | JSON string with dynamic modifications to Kubernetes objects. Supports [placeholders](#placeholders) | `object_modifiers` |

#### Placeholders

Every string in `object_modifiers` (and the ServiceAccount name template) can reference scope data with `${np.<key>}`.
Placeholders in `object_modifiers` are resolved when the scope context is built; the ServiceAccount name template is only evaluated when `service_account_enabled` is `true`.

An unknown or empty placeholder (or an invalid ServiceAccount name) fails scope create/update and deployments instead of rendering an empty value.
Every other action (scope delete, deployment delete, rollback, switch traffic, finalize, ...) logs a warning and continues: `object_modifiers` are left unexpanded and the ServiceAccount is treated as unresolved, so a scope delete leaves it in place.

| Placeholder | Value |
|-------------|-------|
| `${np.account_slug}` | Account slug |
| `${np.namespace_slug}` | nullplatform namespace slug |
| `${np.application_slug}` | Application slug |
| `${np.repository_name}` | Last segment of the application repository URL, without `.git` |
| `${np.scope_slug}` | Scope slug |
| `${np.scope_id}` | Scope id |
| `${np.k8s_namespace}` | Kubernetes namespace the scope is deployed to |
| `${np.dimension.<key>}` | Value of the scope dimension `<key>` (e.g. `${np.dimension.environment}`) |

Only the literal `${np.` prefix is expanded, so Go templates used by annotations (`{{ with secret ... }}`) are left untouched.

Example: per-application annotations for the Vault Agent Injector. With a per-scope [Service Account](#service-account), the pods authenticate with their ServiceAccount token.

```json
{
  "deployment": {
    "annotations": {
      "vault.hashicorp.com/agent-inject": "true",
      "vault.hashicorp.com/role": "apps",
      "vault.hashicorp.com/agent-inject-containers": "application",
      "vault.hashicorp.com/agent-inject-secret-secrets": "kv/data/${np.dimension.environment}/${np.namespace_slug}/${np.application_slug}/secrets"
    }
  }
}
```
