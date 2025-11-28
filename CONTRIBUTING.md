# Contributing to scopes

Thank you for your interest in contributing to the `scopes` repository! This document provides guidelines and information to help you get started.

## Repository Structure

This repository contains implementations for multiple **Custom Scope Providers**. The structure is organized as follows:

-   **`configure`**: A script that sets up the necessary nullplatform entities (Service Specification, Action Specifications, Scope Type, Notification Channel). It uses the `SERVICE_PATH` environment variable to determine which scope to configure.
-   **`entrypoint`**: The main entry point script executed by the nullplatform agent. It receives the event context and routes it to the appropriate service script based on the scope type.
-   **`utils`**: Common utility functions used across scripts.

### Scope Implementations
Each supported scope type has its own directory containing its specific implementation logic:

-   **`k8s/`**: Kubernetes scope implementation.
    -   `specs/`: JSON schemas and templates for the Kubernetes scope.
    -   `scope/`: Workflows for creating, updating, and deleting Kubernetes scopes.
    -   `deployment/`: Workflows for deploying applications to this scope.
-   **`azure/`**: Azure scope implementation.
-   **`scheduled_task/`**: Scheduled Task scope implementation.

## How to Contribute

1.  **Push your changes to a branch**:
    Make your changes and push them to a feature branch in the repository.

2.  **Update your development agent**:
    Configure your local or development agent to use the code from your branch. You can do this by updating the `AGENT_REPO` environment variable or Helm value to point to your branch (e.g., `https://github.com/nullplatform/scopes.git#my-feature-branch`).

3.  **Test the full flow**:
    Trigger the relevant actions in nullplatform and verify that your agent pulls the code from your branch and executes the workflows correctly. The full flow includes:
    -   **Create scope**: Verify scope creation.
    -   **Initial deployment**: Deploy an application to the new scope.
    -   **Blue/Green deployment**: Perform a blue/green deployment and test traffic switching.
    -   **Execute a custom action**: Run any custom actions defined for the scope (if applicable).
    -   **Delete scope**: Verify scope deletion and cleanup.

## Coding Standards

-   **Shell Scripts**: Ensure all shell scripts start with `#!/bin/bash` and use `set -euo pipefail` for robustness.
-   **Formatting**: Keep code clean and readable.
-   **Documentation**: Update the `README.md` if your changes affect the installation or usage instructions.

## Reporting Issues

If you encounter any bugs or have feature requests, please open an issue in the GitHub repository. Provide as much detail as possible to help us understand and resolve the issue.
