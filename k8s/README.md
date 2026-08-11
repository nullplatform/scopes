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

**Note:** These variables are obtained from the `scope-configurations` provider and exported for use in Azure DNS workflows.

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

### Logging

Where application logs are shipped.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **LOGS_PROVIDER** | Default application-log destination: `cloudwatch` or `datadog` (default `cloudwatch`) | `logging.provider` |
| **LOGS_ANNOTATION_PREFIX** | Prefix of the annotation that gates the logs (default `nullplatform.logs`) | `logging.annotation_prefix` |

The deployment stamps one gate annotation on the pod, naming the resolved provider:

```yaml
nullplatform.logs.cloudwatch: 'true'    # or nullplatform.logs.datadog: 'true'
```

The in-cluster logs controller has one routing rule per provider and they are
additive, so emitting exactly one gate is what keeps a pod on exactly one
destination. The annotation is what actually routes the logs; enabling a provider on
the controller only makes its output exist.

When the provider is `cloudwatch`, four `nullplatform.logs.cloudwatch.*` annotations
are stamped alongside it (log group, stream pattern, retention, region). Those are
**naming config, not a gate** — the controller reads them to build the log group and
stream, always under that fixed prefix regardless of `LOGS_ANNOTATION_PREFIX` — so
they are omitted for any other provider.

Any other provider value falls back to `cloudwatch` and logs a warning during the
deployment.

Because the `scope-configurations` provider is resolved for the scope's
dimensions, both settings can be set account-wide or per environment.

A scope can override the *provider* per-scope through the `logs_provider_override`
capability, declared in `specs/service-spec.json.tpl` and surfaced in the UI as
**Logs provider**. Its values are `cloudwatch` / `datadog` plus a `default` sentinel
meaning "delegate to the setting above". A scope without the capability, or with it
set to `default`, follows the account setting. The annotation *prefix* is not
per-scope: it has to match the cluster's logs controller, which is account-wide.

#### Choosing a different annotation prefix

A cluster may already carry `nullplatform.logs.cloudwatch: 'true'` on every
deployment, which leaves that key unable to distinguish workloads that should ship
from ones that should not. Setting `logging.annotation_prefix` to something like
`nullplatform.logs.acme` gives the account a key only these templates emit, so the
blanket one stops gating there.

This has to be done in **two places that must agree**: this setting, and
`CLOUDWATCH_LOGS_ANNOTATION` / `DATADOG_LOGS_ANNOTATION` on that cluster's logs
controller. They cannot change at the same instant, so while the prefix is not the
default the template emits **both** the prefixed key and the default one. The
controller reads whichever it is configured for and never both, so every intermediate
state still delivers one copy to one destination — which makes the rollout order
irrelevant. Once the account's clusters are settled, the dual-emit can be dropped
from the templates.

Two things this does *not* affect: CloudWatch performance metrics and access logs
(they are routed by a different mechanism and keep flowing regardless of this
setting), and the nullplatform log viewer (it reads pod logs through the
Kubernetes API, not from the provider).

Requires the chosen provider to be enabled on the controller. Setting `datadog` while
the controller has Datadog disabled means those logs go nowhere — the routing rule and
the output only exist when `DATADOG_LOGS_ENABLED` is `"true"`.

An earlier revision routed on a single `nullplatform.logs.provider: cloudwatch | datadog`
annotation. Nothing reads it any more and nothing emits it. Note that the gate scheme
is additive: a pod carrying **both** `nullplatform.logs.cloudwatch: 'true'` and
`nullplatform.logs.datadog: 'true'` is delivered to both destinations and billed twice.
These templates derive the gate from one resolved provider, so they never emit both;
anything hand-annotating pods has to maintain that itself.

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
