# Scopes

## What it does
This repository contains the **default implementation** of Scope Providers provided by nullplatform. It allows you to provision and manage infrastructure scopes using the nullplatform agent.

Each top-level directory (e.g., `k8s`, `azure`, `scheduled_task`) represents a distinct **scope** implementation. When a user creates a scope in the nullplatform UI that matches one of these types, the platform sends a notification to the agent, which executes the scripts in this repository to provision and manage that scope.

## Install in your organization

The scopes of this repository are published as **global packages**, visible to every organization. You do not copy their specs: you install a package and use it read-only. How installing a package works, how it coexists with a copy you registered, how to upgrade, and when to fork instead are in the [package installation guide](https://docs.nullplatform.com/docs/packages/install); this section has what is specific to these scopes.

| Package | Directory | Scope type it publishes | Worker image | Overlay |
|---|---|---|---|---|
| `np-containers` | `k8s/` | Containers | `scopes/containers` | none |
| `np-containers-on-premise` | `onprem/` | Containers (On-Premise), with a scope configuration | `scopes/containers` | `NP_OVERRIDES_PATH=/app/pkg/onprem` |
| `np-scheduled-task` | `scheduled_task/` | Scheduled task | `scopes/scheduled-task` | baked into the image |

Both containers packages pin the same image: it bakes the whole repository with `k8s` as the service path, and on-premise is the overlay its worker runs, set through `NP_OVERRIDES_PATH` on the worker pod (`scheduled_task` sets its own overlay in its image). **AKS and ARO clusters install `np-containers`**: the code is the same, and what the `azure/` and `azure-aro/` directories set (`DNS_TYPE`, `K8S_FLAVOR`) comes from the agent's environment in the worker model, as it does today. Metrics are not an overlay: the metric step reads the organization's metrics provider (Prometheus or Datadog) and queries that source, so one image serves both (`datadog/` only remains as a compatibility overlay for channels that still pass it as `--overrides-path`).

Already registered a copy with `./configure` or tofu-modules' `scope_definition` (slug `containers`, `scheduled-task`, ...)? It keeps working: those specs stay in every release, and the packages install next to it, as the guide explains. The `np-` prefix is what lets both live in one organization: channels route by specification slug.

Installing a package touches the same three layers as registering a scope yourself, and only the nullplatform layer changes:

| Layer | What | Module |
|---|---|---|
| infrastructure (cloud credentials) | On AWS, the permissions role the worker assumes for IAM, ELBv2, Route 53, S3 and CloudWatch | [`k8s/specs/requirements/aws`](./k8s/specs/requirements/aws) |
| nullplatform (nullplatform API key) | The installation of the package, the scope type, the NRN settings and, for on-premise, the scope-configuration schema | tofu-modules' `scope_package_installation` |
| bindings | The agent channel, the role under selector `containers` in your IAM provider (`CONTAINERS_ASSUME_ROLE_SELECTOR`), and the agent's worker settings | tofu-modules' `scope_definition_agent_association`, `nullplatform/agent`, your providers |

Pick ONE release of this repository (the latest is on its [releases page](https://github.com/nullplatform/scopes/releases)) and use its version in every place below. `np-containers` shown; the other two change the slug and the name, on-premise also sets `create_scope_configuration` and the worker patch.

```hcl
# ── infrastructure layer (AWS) ───────────────────────────────────────
module "containers_requirements" {
  source = "git::https://github.com/nullplatform/scopes.git//k8s/specs/requirements/aws?ref=vX.Y.Z"

  cluster_name   = "my-cluster"
  agent_role_arn = module.agent_iam.nullplatform_agent_role_arn
}

# The agent role must be allowed to assume it: add it to the assume_role_arns
# of tofu-modules' infrastructure/aws/iam/agent.
#   assume_role_arns = [..., module.containers_requirements.permissions_role_arn]

# ── nullplatform layer ───────────────────────────────────────────────
module "containers" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_package_installation?ref=v9.16.0"

  nrn             = var.nrn
  np_api_key      = var.np_api_key # for the NRN settings patch (np nrn patch)
  package_slug    = "np-containers"
  package_version = "X.Y.Z" # the same release, without the v

  # Yours, created from this repository's templates at the same release:
  service_spec_name                = "Containers" # the scope type developers pick
  service_spec_description         = "Docker containers on pods"
  service_path                     = "k8s"
  repository_scope_template        = "https://raw.githubusercontent.com/nullplatform/scopes/refs/tags"
  repository_scope_template_branch = "vX.Y.Z" # the same release
  create_scope_configuration       = false # true for np-containers-on-premise (service_path = "onprem")
  create_agent_channel             = false # the channel lives in your bindings layer, below
}

# ── bindings layer ───────────────────────────────────────────────────
# containers_requirements and containers come from the other layers (remote state).
module "containers_channel" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=v9.16.0"

  nrn                      = var.nrn
  tags_selectors           = { cluster = "runtime" } # must match the agent's TAGS
  scope_specification_id   = local.containers.service_specification_id
  scope_specification_slug = local.containers.service_specification_slug
  service_path             = "k8s"

  # The channel template, from the same tag
  repository_notification_channel        = "https://raw.githubusercontent.com/nullplatform/scopes/refs/tags"
  repository_notification_channel_branch = "vX.Y.Z" # the same release

  worker_orchestrator = true
  package_slug        = local.containers.package_slug
}

# One aws-iam-configuration per NRN and dimensions: add the entry to the list
# your IAM provider already has.
#   { selector = "containers", arn = local.containers_requirements.permissions_role_arn }

# ── agent (tofu-modules' nullplatform/agent) ─────────────────────────
# Every package here runs the k8s scope code, so it needs the k8s
# environment the module injects (worker_k8s_packages: DNS_TYPE, K8S_NAMESPACE,
# CLUSTER_NAME, the template paths, extra_envs) and the agent's identity
# (worker_orchestrated_packages). On AKS and ARO, dns_type = "azure" and
# extra_envs = { K8S_FLAVOR = "aks" } (or "aro") are what the azure/ and
# azure-aro/ directories used to set. On-premise also needs the worker patch
# that picks its overlay directory.
#   worker_orchestrated_packages = ["np-containers", "np-scheduled-task"]
#   worker_k8s_packages          = ["np-containers", "np-scheduled-task"]
#
#   worker = {
#     patches = [{
#       target = { package = "np-containers-on-premise" }
#       merge  = { spec = { containers = [{
#         name = "worker"
#         env  = [{ name = "NP_OVERRIDES_PATH", value = "/app/pkg/onprem" }]
#       }] } }
#     }]
#   }
```

The scope's settings (`k8s/values.yaml` keys, documented in [`k8s/README.md`](./k8s/README.md)) are read from the worker environment and the providers, as for a registered copy. To upgrade, move the release in every layer: `ref` of the requirements module, `package_version` and `repository_scope_template_branch` of the installation and `repository_notification_channel_branch` of the channel. See tofu-modules' [`scope_package_installation`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/scope_package_installation) for its inputs and outputs.

Prerequisites: an agent whose `TAGS` match the channel's `tags_selectors`, with the package slugs in `worker_orchestrated_packages` and `worker_k8s_packages`, and `public.ecr.aws/nullplatform/*` in `worker.allowedRegistries`.

Every tag publishes a new revision of the three packages from this repository: [`publish-images.yml`](./.github/workflows/publish-images.yml) pushes the images, registers them as artifacts and applies each `<directory>/publish` stack (tofu-modules' `scope_package_publish`) with the digest of the image that scope runs. The package version is the tag; a prerelease tag (`v1.21.0-beta.1`) publishes without moving the package default.

## Installing a Custom Scope

This is the own-copy path: it registers the specs of a checkout in your organization and the agent clones this repository. To use the published packages instead, see [Install in your organization](#install-in-your-organization).

This guide follows the [Production-ready Kubernetes](https://docs.nullplatform.com/docs/how-to-guides/kubernetes-prod-ready) setup as a primary example, but the steps are similar for other scopes.

### Prerequisites
-   Access to a Kubernetes cluster (for the agent).
-   [Helm](https://helm.sh/docs/intro/install/) installed.
-   [Gomplate](https://docs.gomplate.ca/) installed.
-   The [nullplatform CLI](https://docs.nullplatform.com/docs/cli/) installed.
-   An [API key](https://docs.nullplatform.com/docs/authorization/api-keys) at the account level with roles: `Agent`, `Developer`, `Ops`, `SecOps`, and `Secrets Reader`.

### Installation Steps

#### 1. Install the nullplatform agent (Helm)

Add the Helm repo:
```bash
helm repo add nullplatform https://nullplatform.github.io/helm-charts
helm repo update
```

Install the agent chart:
```bash
helm install nullplatform-agent nullplatform/nullplatform-agent \
  --set configuration.values.NP_API_KEY=$NP_API_KEY \
  --set configuration.values.TAGS="$AGENT_TAGS" \
  --set configuration.values.AGENT_REPO=$AGENT_REPO
```

**Environment Variables for Agent:**
-   `NP_API_KEY`: Your account-level API key.
-   `AGENT_TAGS`: Tags to identify this agent (e.g., `environment:production,scope:k8s`).
-   `AGENT_REPO`: `https://github.com/nullplatform/scopes.git#main`

#### 2. Clone the scopes repository

Clone this repository to your local machine or the environment where you will run the configuration script:

```bash
git clone https://github.com/nullplatform/scopes.git
cd scopes
```

#### 3. Configure scope environment variables

Set the variables required by the configuration script. **Crucially, `SERVICE_PATH` determines which scope you are configuring (e.g., `k8s`, `azure`).**

```bash
export NP_API_KEY=<your_api_key_here>
export NRN=<your_resource_nrn>
export REPO_PATH=/root/.np/nullplatform/scopes
export SERVICE_PATH=k8s  # <--- Selects the Kubernetes scope implementation
export ENVIRONMENT=production
```

-   `NRN`: Target resource NRN (from the UI).
-   `ENVIRONMENT`: Must match the environment tag in your `AGENT_TAGS`.

#### 4. Configure the Scope

Run the configuration script to register the scope schema, actions, and the agent notification channel:

```bash
./configure
```

The script will:
-   Register the JSON schema for the selected scope (from `$SERVICE_PATH`).
-   Create action specifications (e.g., `create-scope`, `delete-scope`).
-   Register the scope type.
-   Set up a notification channel for your agent.

## Repository Structure

-   **`configure`**: The setup script that registers the provider with nullplatform.
-   **`entrypoint`**: The main script executed by the agent. It routes events to the appropriate scope implementation.
-   **`k8s/`**: Kubernetes scope implementation.
    -   `specs/`: JSON schemas and templates.
    -   `scope/`: Lifecycle workflows (create, update, delete).
    -   `diagnose/`: Diagnostic workflows and checks for troubleshooting (scope, service, networking diagnostics).
    -   `deployment/`: Deployment configuration and templates.
    -   `backup/`: Backup workflows and utilities.
    -   `instance/`: Instance management workflows.
    -   `log/`: Log collection and processing workflows.
    -   `metric/`: Metrics collection workflows.
    -   `parameters/`: Parameter management workflows.
    -   `publish/`: publishes the scope as the global package `np-containers` (release workflow only).
-   **`azure/`**, **`azure-aro/`**: config overlays of the Kubernetes scope for the legacy git-clone channel (specs and `values.yaml`); not packages.
-   **`onprem/`**: config overlay for clusters with no cloud behind them, with its scope-configuration schema and its `publish/`.
-   **`scheduled_task/`**: Scheduled Tasks scope implementation, with its `publish/`.
-   **`agent/`**: Agent deployment scripts.

## Tracing overrides

Override workflows (`--overrides-path`) merge into the base workflow by step name. How their steps show up in the trace:

-   **Replacing a base step** (same name) keeps the base step's `trace:` block unless the override declares its own.
-   **Adding a step** to a workflow with `trace.default: false` (most deployment workflows) leaves it out of the trace. Give it a `trace:` block so it gets its own step, and its failures land there and not only on the run:

    ```yaml
    - name: register api gateway route
      type: script
      file: "$OVERRIDES_PATH/deployment/register_route"
      trace:
        title: Register the API gateway route
        group: setting-up   # one of the base workflow's trace.groups
    ```
-   Override scripts share the workflow shell, so `log error` and the `np_scope_*` helpers from the scope type's `logging` work in them. `log error "❌ <cause>"` becomes the step's traced error, and `np_scope_failure <reason>` labels the step and run with `failure.reason`.

## IDE Support for Workflow YAML

To enable autocomplete and validation for workflow YAML files (`**/workflows/*.yaml`), you can configure your IDE to use the provided `workflow.schema.json`.

### VS Code
1.  Copy `workflow.schema.json` to your project root.
2.  Add the following to your `.vscode/settings.json`:
    ```json
    {
      "yaml.schemas": {
        "workflow.schema.json": "**/workflows/*.yaml"
      }
    }
    ```
3.  Install the **YAML** extension by RedHat.

### JetBrains (IntelliJ, GoLand, etc.)
1.  Go to **Preferences** -> **Languages & Frameworks** -> **Schemas and DTDs** -> **JSON Schema**.
2.  Create a new schema mapping.
3.  Select the `workflow.schema.json` file.
4.  Add a file path pattern: `**/workflows/*.yaml`.

## About
This repository is part of the nullplatform examples collection, designed to help you build and manage your own internal developer platform.