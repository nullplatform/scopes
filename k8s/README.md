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

#### Namespace per nullplatform namespace

`K8S_NAMESPACE` (or `cluster.namespace`) may be a pattern instead of a fixed name. It uses the same `{.path}`
placeholders and engine as the resource naming patterns (`docs/resource-naming.md`), so it can read any context field:

| `K8S_NAMESPACE` / `cluster.namespace` | Kubernetes namespace |
|---|---|
| `nullplatform` | `nullplatform`: every scope in one namespace (default) |
| `{.namespace.slug}` | `payments`: one per nullplatform namespace |
| `{.account.slug}-{.namespace.slug}` | `acme-payments`: for clusters shared by several accounts |
| `{.namespace.slug}-{.scope.dimensions.environment}` | `payments-production`: one per environment |

Each placeholder must point at a single value (`{.scope.dimensions.environment}`, not `{.scope.dimensions}`), fixed
text goes before the first placeholder or after the last one, and the rendered name must be a valid Kubernetes
namespace name. The namespace is created on first use when `CREATE_K8S_NAMESPACE_IF_NOT_EXIST` is true, labeled
`nullplatform=true`. Nothing is copied into it: image pull secrets, the traffic manager ConfigMap or any other object the
scopes need there come from a workflow override (`OVERRIDES_PATH`) or from the cluster's own tooling.

A pattern never renders a namespace a scope must not run in: `default`, `kube-*`, the gateway namespace
(`GATEWAY_NAMESPACE`), those of the additional gateways and, when the agent runs in the cluster, its own namespace are
refused. A rendered namespace that already exists is reused only if it carries the label `nullplatform=true`; label one
created by hand with `kubectl label namespace <name> nullplatform=true`.

A scope that already has objects in the cluster stays in their namespace (`utils/resolve_k8s_namespace`) if that
namespace is trusted: the configured fixed name, the default `nullplatform`, or one labeled `nullplatform=true`. Labels
prove nothing (anyone who can create an object can set them), so objects in other namespaces are ignored when a trusted
one has the scope's objects, the action fails when several trusted namespaces have them, and it fails when only
untrusted ones do. After changing a fixed namespace, label the old one so its scopes keep working, `default` included.

Finding a scope's objects lists deployments, services, cronjobs and jobs in every namespace. If the agent cannot, a
fixed namespace is used as configured; with a pattern the action fails instead of rendering a new namespace for an
existing scope. Diagnose still runs when the namespace is refused, in the namespace of the scope's pods. Kubernetes
namespaces are never deleted.

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
| **GATEWAY_NAMESPACE** | Namespace of the public and private gateways (default `gateways`). Also read from `gateway.namespace` in the container-orchestration provider | `networking.gateway_namespace` |
| _additional public gateways_ | Extra gateways the HTTPRoute of public scopes is attached to, as a list of `{"name", "namespace"}` (namespace defaults to the gateway namespace). Also read from `gateway.additional_public_gateways` in the container-orchestration provider | `networking.additional_public_gateways` |
| _additional private gateways_ | Same as above, for private scopes | `networking.additional_private_gateways` |
| **GATEWAY_EXTERNAL_IP** | Address published in DNS instead of the one detected from the cluster. Set it when a NAT/VIP device fronts the gateway, so records carry the externally reachable address rather than the internal one. An IPv4 value yields an A record, a hostname a CNAME. | _environment variable_ |

**Note:** `GATEWAY_EXTERNAL_IP` is read straight from the agent's environment, not from the
`scope-configurations` provider, and only applies to the `external_dns` DNS type. Left unset,
the address is auto-detected from the Gateway or its Service, which is correct whenever no
address translation sits in front of the cluster.

Every gateway the HTTPRoute references must exist before it is applied, and the deployment
waits until each of them reports `Accepted` and `ResolvedRefs`. DNS records keep pointing at
the main gateway only. The agent needs `get` on `gateways` in every namespace configured.

#### Service-to-service

A scope on the Istio HTTPRoute templates can get a stable in-cluster name,
`{app}-{scope}.{namespace}.svc.cluster.local`, routed through a gateway with the scope's blue-green
weights. Off by default; see `k8s/docs/service-to-service.md`.

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **SERVICE_TO_SERVICE_ENABLED** | Create the stable name (default `false`) | `networking.service_to_service.enabled` |
| **SERVICE_TO_SERVICE_MODE** | `shared` (the private gateway) or `dedicated` (`gateway-in-cluster`) | `networking.service_to_service.mode` |

### Deployment

#### General

| Variable | Description | Scope Configuration Property |
|----------|-------------|------------------------------|
| **DEPLOY_STRATEGY** | Deployment strategy (rolling or blue-green) | `deployment.deployment_strategy` |
| **DEPLOYMENT_MAX_WAIT_IN_SECONDS** | Maximum wait time for deployments (seconds) | `deployment.deployment_max_wait_seconds` |
| **PRESTOP_SLEEP_MODE** | preStop wait before SIGTERM: `exec` (default, `/bin/sleep` in the image) or `native` (kubelet sleep action, works on images without `/bin/sleep`; every node must run Kubernetes >= 1.30) | `deployment.prestop_sleep_mode` |
| **TRAFFIC_PROXY** | What carries a scope's HTTP traffic and metrics: `nginx` (default, traffic-manager sidecar in every pod) or `istio` (no sidecar; the Istio gateway access log feeds the logs-controller, which needs `ISTIO_ACCESS_LOGS_ENABLED`). Additional ports run without their sidecars and only the main port gates readiness. Not supported with `GATEWAY_TYPE=aro_cluster` | `deployment.traffic_proxy` |
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

The `IAM` block in `values.yaml` also accepts:

- `PREFIX` as a pattern rendered by the resource naming engine, e.g. `{.account.slug}-{.namespace.slug}`; the role and its service account are named `<rendered prefix>-<scope id>`. A prefix without `{` is used as is. A scope that already has a service account keeps its name if its role is tagged with the scope id. See `k8s/docs/resource-naming.md`.
- `MODE`: `irsa` (default) trusts the cluster's OIDC provider and annotates the service account with the role ARN; `pod_identity` trusts EKS Pod Identity and creates a pod identity association for the scope's service account. The cluster needs the EKS Pod Identity Agent, and the agent role needs `eks:CreatePodIdentityAssociation`, `eks:ListPodIdentityAssociations`, `eks:DeletePodIdentityAssociation`, `eks:TagResource` and `iam:PassRole` on `/nullplatform/custom-scopes/`. The mode applies to scopes created after it changes; recreate a scope to move it to the other mode.
- `TAGS`: additional tags for the role (and the pod identity association). A value with `{` is a pattern rendered by the same engine; any other value is used as is. A key that nullplatform already sets (`scope_id`, `application`, a dimension, …) is rejected.

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

## Create Form Variables

These variables change the scope's create form, not its workflows. They are read by gomplate when `specs/service-spec.json.tpl` is rendered: pass them in `template_env_vars` of tofu-modules' `scope_definition`, or export them before running `./configure`. A published package (`np-containers`) renders its spec once, without them, so they do not apply to it.

| Variable | Description | Default |
|----------|-------------|---------|
| **DEFAULT_VISIBILITY** | Visibility preselected for new scopes: `public` or `internal` (`private` is an alias of `internal`) | `internal`, or the only option left by `VISIBILITY_OPTIONS` |
| **VISIBILITY_OPTIONS** | Comma-separated visibility options the form offers: `public` and `internal` (labeled "Internet" and "Private" by default); `private` is an alias of `internal`. With a single option the form shows no Visibility selector and new scopes get that option | `public,internal` |
| **VISIBILITY_PUBLIC_LABEL** | Label of the `public` option in the form. Only the text changes: the scope is still stored as `public` | `Internet` |
| **VISIBILITY_INTERNAL_LABEL** | Label of the `internal` option in the form. Only the text changes: the scope is still stored as `internal` | `Private` |

All are trimmed, and an empty value means the default. `DEFAULT_VISIBILITY` and `VISIBILITY_OPTIONS` are case-insensitive; the labels are shown as written (`scope_definition` does not accept a single quote in any value). A label only shows when the form offers both options. The render fails on an unknown value, on a `VISIBILITY_OPTIONS` with no option left, or on a `DEFAULT_VISIBILITY` that `VISIBILITY_OPTIONS` does not offer. The spec's schema keeps accepting both values, so existing scopes stay valid whatever `VISIBILITY_OPTIONS` says. For example, to create only scopes reachable through the private gateway, with no Visibility selector in the form:

```hcl
template_env_vars = {
  VISIBILITY_OPTIONS = "internal"
}
```

Or, to keep both options and rename the private one:

```hcl
template_env_vars = {
  VISIBILITY_INTERNAL_LABEL = "Internal"
}
```
