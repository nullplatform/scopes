# Scopes

## What it does
This repository contains the **default implementation** of Scope Providers provided by nullplatform. It allows you to provision and manage infrastructure scopes using the nullplatform agent.

Each top-level directory (e.g., `k8s`, `azure`, `scheduled_task`) represents a distinct **scope** implementation. When a user creates a scope in the nullplatform UI that matches one of these types, the platform sends a notification to the agent, which executes the scripts in this repository to provision and manage that scope.

## Installing a Custom Scope

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
-   **`azure/`**: Azure scope implementation.
-   **`scheduled_task/`**: Scheduled Tasks scope implementation.
-   **`agent/`**: Agent deployment scripts.

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