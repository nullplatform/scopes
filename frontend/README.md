# Frontend Deployment Module

This module provides infrastructure-as-code for deploying static frontend applications across multiple cloud providers. It uses a **layered architecture** that separates concerns and enables mix-and-match combinations of providers, DNS solutions, and CDN/hosting platforms.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Layer System](#layer-system)
- [Variable Naming Conventions](#variable-naming-conventions)
- [Cross-Layer Communication](#cross-layer-communication)
- [Adding New Layer Implementations](#adding-new-layer-implementations)
- [Setup Script Patterns](#setup-script-patterns)
- [Testing](#testing)
- [Quick Reference](#quick-reference)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        WORKFLOW ENGINE                          │
│  (workflows/initial.yaml, workflows/delete.yaml)                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      LAYER COMPOSITION                          │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   PROVIDER   │  │   NETWORK    │  │    DISTRIBUTION      │  │
│  │    LAYER     │──▶    LAYER     │──▶       LAYER          │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                 │
│  Implementations:   Implementations:   Implementations:         │
│  • aws              • route53          • cloudfront             │
│  • azure            • azure_dns        • blob-cdn               │
│  • gcp              • cloud_dns        • amplify                │
│                                        • firebase               │
│                                        • gcs-cdn                │
│                                        • static-web-apps        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TERRAFORM/OPENTOFU                          │
│  (composed modules from all active layers)                      │
└─────────────────────────────────────────────────────────────────┘
```

### Layer Flow

1. **Provider Layer**: Configures cloud credentials, state backend, and resource tags
2. **Network Layer**: Sets up DNS zones and records, calculates domains
3. **Distribution Layer**: Deploys CDN/hosting with references to network outputs

---

## Layer System

Each layer consists of two components:

### 1. Setup Script (`setup`)

A bash script that:
- Validates required inputs (environment variables, context)
- Fetches external data (cloud APIs, nullplatform API)
- Updates `TOFU_VARIABLES` with layer-specific configuration
- Registers the module directory in `MODULES_TO_USE`

### 2. Modules Directory (`modules/`)

Terraform/OpenTofu files:
- `main.tf` - Resource definitions
- `variables.tf` - Input variable declarations
- `locals.tf` - Computed values and cross-layer references
- `outputs.tf` - Exported values for other layers
- `test_locals.tf` - Test-only stubs (skipped during composition)

### Directory Structure

```
frontend/deployment/
├── provider/
│   └── {cloud}/
│       ├── setup              # Validation & module registration
│       └── modules/
│           ├── provider.tf    # Backend & provider config
│           └── variables.tf
│
├── network/
│   └── {dns_provider}/
│       ├── setup
│       └── modules/
│           ├── main.tf
│           ├── variables.tf
│           ├── locals.tf
│           ├── outputs.tf
│           └── test_locals.tf
│
├── distribution/
│   └── {cdn_provider}/
│       ├── setup
│       └── modules/
│           ├── main.tf
│           ├── variables.tf
│           ├── locals.tf
│           ├── outputs.tf
│           └── test_locals.tf
│
├── scripts/                   # Shared helper scripts
├── workflows/                 # Workflow definitions
└── tests/                     # Unit and integration tests
```

---

## Variable Naming Conventions

**All variables MUST use layer-prefixed naming** for clarity and to avoid conflicts:

| Layer | Prefix | Examples |
|-------|--------|----------|
| **Provider** | `{cloud}_provider` | `azure_provider`, `aws_provider`, `gcp_provider` |
| **Provider** | `provider_*` | `provider_resource_tags_json` |
| **Network** | `network_*` | `network_domain`, `network_subdomain`, `network_full_domain`, `network_dns_zone_name` |
| **Distribution** | `distribution_*` | `distribution_storage_account`, `distribution_app_name`, `distribution_blob_prefix` |

### Provider Object Structure

Each cloud provider uses an object variable:

```hcl
# Azure
variable "azure_provider" {
  type = object({
    subscription_id = string
    resource_group  = string
    storage_account = string  # For Terraform state
    container       = string  # For Terraform state
  })
}

# AWS
variable "aws_provider" {
  type = object({
    region       = string
    state_bucket = string
    lock_table   = string
  })
}

# GCP
variable "gcp_provider" {
  type = object({
    project = string
    region  = string
    bucket  = string
  })
}
```

### Cross-Layer Shared Variables

These variables are used by multiple layers and MUST use consistent naming across implementations:

| Variable | Set By | Used By | Description |
|----------|--------|---------|-------------|
| `network_full_domain` | Network | Distribution | Full domain (e.g., `app.example.com`) |
| `network_domain` | Network | Distribution | Base domain (e.g., `example.com`) |
| `network_subdomain` | Network | Distribution | Subdomain part (e.g., `app`) |
| `distribution_target_domain` | Distribution | Network | CDN endpoint hostname for DNS record |
| `distribution_record_type` | Distribution | Network | DNS record type (`CNAME` or `A`) |

---

## Cross-Layer Communication

Layers communicate through **locals** that are merged when modules are composed together.

### How It Works

1. Each layer defines locals in `locals.tf`
2. When modules are composed, all locals are merged into a single namespace
3. Layers can reference each other's locals directly

### Example: Network → Distribution

**Network layer exports** (`network/azure_dns/modules/locals.tf`):
```hcl
locals {
  network_full_domain = "${var.network_subdomain}.${var.network_domain}"
  network_domain      = var.network_domain
}
```

**Distribution layer consumes** (`distribution/blob-cdn/modules/locals.tf`):
```hcl
locals {
  # References network layer's local directly
  distribution_has_custom_domain = local.network_full_domain != ""
  distribution_full_domain       = local.network_full_domain
}
```

### Test Locals (`test_locals.tf`)

For unit testing modules in isolation, use `test_locals.tf` to stub cross-layer dependencies:

```hcl
# File: test_locals.tf
# NOTE: Files matching test_*.tf are skipped by compose_modules

variable "network_full_domain" {
  description = "Test-only: Simulates network layer output"
  default     = ""
}

locals {
  network_full_domain = var.network_full_domain
}
```

---

## Adding New Layer Implementations

### Quick Start with Boilerplate Script

Use the provided script to generate the folder structure:

```bash
# Create a new network layer implementation
./scripts/setup-layer --type network --name cloudflare

# Create a new distribution layer implementation
./scripts/setup-layer --type distribution --name netlify

# Create a new provider layer implementation
./scripts/setup-layer --type provider --name digitalocean
```

This creates:
```
frontend/deployment/{type}/{name}/
├── setup                    # Boilerplate setup script
└── modules/
    ├── main.tf              # Empty, ready for resources
    ├── variables.tf         # Layer-prefixed variables
    ├── locals.tf            # Cross-layer locals
    ├── outputs.tf           # Layer outputs
    └── test_locals.tf       # Test stubs
```

### Manual Steps After Generation

1. **Edit `setup` script**: Add validation logic and TOFU_VARIABLES updates
2. **Edit `modules/main.tf`**: Add Terraform resources
3. **Edit `modules/variables.tf`**: Define required inputs
4. **Update `modules/locals.tf`**: Add cross-layer references
5. **Add tests**: Create `tests/{type}/{name}/` with `.tftest.hcl` files

---

## Setup Script Patterns

### Required Structure

Every setup script must:

```bash
#!/bin/bash
# =============================================================================
# {Layer Type}: {Implementation Name}
#
# Brief description of what this layer does.
# =============================================================================

set -euo pipefail

# 1. VALIDATION PHASE
echo "🔍 Validating {Implementation} configuration..."
echo ""

# Validate required variables
if [ -z "${REQUIRED_VAR:-}" ]; then
  echo "   ❌ REQUIRED_VAR is missing"
  echo ""
  echo "  💡 Possible causes:"
  echo "    • Variable not set in environment"
  echo ""
  echo "  🔧 How to fix:"
  echo "    • Set REQUIRED_VAR in your environment"
  exit 1
fi
echo "   ✅ REQUIRED_VAR=$REQUIRED_VAR"

# 2. EXTERNAL DATA FETCHING (if needed)
echo ""
echo "   📡 Fetching {resource}..."
# Call APIs, validate responses

# 3. UPDATE TOFU_VARIABLES
TOFU_VARIABLES=$(echo "$TOFU_VARIABLES" | jq \
  --arg var_name "$var_value" \
  '. + {
    layer_variable_name: $var_name
  }')

# 4. REGISTER MODULE
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
module_name="${script_dir}/modules"

if [[ -n ${MODULES_TO_USE:-} ]]; then
  MODULES_TO_USE="$MODULES_TO_USE,$module_name"
else
  MODULES_TO_USE="$module_name"
fi

echo ""
echo "✨ {Implementation} configured successfully"
echo ""
```

### Logging Conventions

| Icon | Usage |
|------|-------|
| `🔍` | Starting validation phase |
| `✅` | Successful validation |
| `❌` | Failed validation |
| `📡` | Fetching external data |
| `📝` | Performing an action |
| `💡` | Possible causes of error |
| `🔧` | How to fix instructions |
| `📋` | Debug information |
| `✨` | Success summary |

### Error Handling Pattern

```bash
if [ $? -ne 0 ]; then
  echo "   ❌ Failed to {action}"
  echo ""

  # Classify error type
  if echo "$output" | grep -q "NotFound"; then
    echo "  🔎 Error: Resource not found"
  elif echo "$output" | grep -q "Forbidden\|403"; then
    echo "  🔒 Error: Permission denied"
  else
    echo "  ⚠️  Error: Unknown error"
  fi

  echo ""
  echo "  💡 Possible causes:"
  echo "    • Cause 1"
  echo "    • Cause 2"
  echo ""
  echo "  🔧 How to fix:"
  echo "    1. Step 1"
  echo "    2. Step 2"
  echo ""
  echo "  📋 Error details:"
  echo "$output" | sed 's/^/    /'

  exit 1
fi
```

---

## Testing

We use **three types of tests** to ensure quality at different levels:

| Test Type | What it Tests | Location | Command |
|-----------|---------------|----------|---------|
| **Unit Tests (BATS)** | Bash setup scripts | `tests/{layer_type}/{name}/` | `make test-unit` |
| **Tofu Tests** | Terraform modules | `{layer_type}/{name}/modules/*.tftest.hcl` | `make test-tofu` |
| **Integration Tests** | Full workflow execution | `tests/integration/test_cases/` | `make test-integration` |

### 1. Unit Tests (BATS)

Test bash setup scripts in isolation using mocked commands.

**Location:** `frontend/deployment/tests/{layer_type}/{name}/setup_test.bats`

**Run:** `make test-unit` or `make test-unit MODULE=frontend`

**Example files:**
- Provider: [`tests/provider/azure/setup_test.bats`](deployment/tests/provider/azure/setup_test.bats)
- Network: [`tests/network/azure_dns/setup_test.bats`](deployment/tests/network/azure_dns/setup_test.bats)
- Distribution: [`tests/distribution/blob-cdn/setup_test.bats`](deployment/tests/distribution/blob-cdn/setup_test.bats)

**Structure:**
```bash
#!/usr/bin/env bats

setup() {
  # Mock external commands (jq, az, aws, np, etc.)
  # Set required environment variables
  export CONTEXT='{"key": "value"}'
  export TOFU_VARIABLES='{}'
}

@test "validates required environment variable" {
  unset REQUIRED_VAR
  run source_setup
  assert_failure
  assert_output --partial "REQUIRED_VAR is missing"
}

@test "sets TOFU_VARIABLES correctly" {
  export REQUIRED_VAR="test-value"
  run source_setup
  assert_success
  # Check TOFU_VARIABLES was updated correctly
}
```

### 2. Tofu Tests (OpenTofu/Terraform)

Test Terraform modules using `tofu test` with mock providers.

**Location:** `frontend/deployment/{layer_type}/{name}/modules/{name}.tftest.hcl`

**Run:** `make test-tofu` or `make test-tofu MODULE=frontend`

**Example files:**
- Provider: [`provider/azure/modules/provider.tftest.hcl`](deployment/provider/azure/modules/provider.tftest.hcl)
- Network: [`network/azure_dns/modules/azure_dns.tftest.hcl`](deployment/network/azure_dns/modules/azure_dns.tftest.hcl)
- Distribution: [`distribution/blob-cdn/modules/blob-cdn.tftest.hcl`](deployment/distribution/blob-cdn/modules/blob-cdn.tftest.hcl)

**Structure:**
```hcl
# =============================================================================
# Mock Providers
# =============================================================================
mock_provider "azurerm" {}

# =============================================================================
# Test Variables
# =============================================================================
variables {
  network_domain    = "example.com"
  network_subdomain = "app"
}

# =============================================================================
# Tests
# =============================================================================
run "test_dns_record_created" {
  command = plan

  assert {
    condition     = azurerm_dns_cname_record.main[0].name == "app"
    error_message = "CNAME record name should be 'app'"
  }
}

run "test_full_domain_output" {
  command = plan

  assert {
    condition     = output.network_full_domain == "app.example.com"
    error_message = "Full domain should be 'app.example.com'"
  }
}
```

### 3. Integration Tests (BATS)

Test complete workflows with mocked external dependencies (LocalStack, Azure Mock, Smocker).

**Location:** `frontend/deployment/tests/integration/test_cases/{scenario}/lifecycle_test.bats`

**Run:** `make test-integration` or `make test-integration MODULE=frontend`

**Example file:** [`tests/integration/test_cases/azure_blobcdn_azuredns/lifecycle_test.bats`](deployment/tests/integration/test_cases/azure_blobcdn_azuredns/lifecycle_test.bats)

**What's mocked:**
- **LocalStack**: AWS services (S3, Route53, STS, IAM, DynamoDB, ACM)
- **Moto**: CloudFront (not in LocalStack free tier)
- **Azure Mock**: Azure ARM APIs (CDN, DNS, Storage) + Blob Storage
- **Smocker**: nullplatform API

**Structure:**
```bash
#!/usr/bin/env bats

# Test constants derived from context
TEST_DISTRIBUTION_APP_NAME="my-app"
TEST_NETWORK_DOMAIN="example.com"

setup_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  integration_setup --cloud-provider azure  # or: aws
  # Pre-create required resources in mocks
}

teardown_file() {
  integration_teardown
}

setup() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  load_context "frontend/deployment/tests/resources/context.json"

  # Configure layer selection
  export NETWORK_LAYER="azure_dns"
  export DISTRIBUTION_LAYER="blob-cdn"
  export TOFU_PROVIDER="azure"

  # Setup API mocks
  mock_request "GET" "/provider" "mocks/provider.json"
}

@test "create infrastructure deploys resources" {
  run_workflow "frontend/deployment/workflows/initial.yaml"

  assert_azure_cdn_configured "$TEST_DISTRIBUTION_APP_NAME" ...
  assert_azure_dns_configured "$TEST_NETWORK_DOMAIN" ...
}

@test "destroy infrastructure removes resources" {
  run_workflow "frontend/deployment/workflows/delete.yaml"

  assert_azure_cdn_not_configured ...
  assert_azure_dns_not_configured ...
}
```

### Running Tests

```bash
# Run all tests
make test-all

# Run specific test types
make test-unit              # BATS unit tests for bash scripts
make test-tofu              # OpenTofu module tests
make test-integration       # Full workflow integration tests

# Run tests for specific module
make test-unit MODULE=frontend
make test-tofu MODULE=frontend
make test-integration MODULE=frontend

# Run with verbose output (integration only)
make test-integration VERBOSE=1
```

---

## Quick Reference

### Environment Variables by Provider

#### AWS
```bash
export TOFU_PROVIDER=aws
export AWS_REGION=us-east-1
export TOFU_PROVIDER_BUCKET=my-state-bucket
export TOFU_LOCK_TABLE=my-lock-table
```

#### Azure
```bash
export TOFU_PROVIDER=azure
export AZURE_SUBSCRIPTION_ID=xxx
export AZURE_RESOURCE_GROUP=my-rg
export TOFU_PROVIDER_STORAGE_ACCOUNT=mystateaccount
export TOFU_PROVIDER_CONTAINER=tfstate
```

#### GCP
```bash
export TOFU_PROVIDER=gcp
export GOOGLE_PROJECT=my-project
export GOOGLE_REGION=us-central1
export TOFU_PROVIDER_BUCKET=my-state-bucket
```

### Layer Selection

```bash
export NETWORK_LAYER=route53        # or: azure_dns, cloud_dns
export DISTRIBUTION_LAYER=cloudfront # or: blob-cdn, amplify, firebase, etc.
```

---

## AI Assistant Prompt for Implementing New Layers

When asking an AI assistant to help implement a new layer, just paste this prompt:

````
I need to implement a new layer in the frontend deployment module.

**IMPORTANT:** Before starting:

1. Read `frontend/README.md` to understand:
   - The layer system architecture and how layers interact
   - Variable naming conventions (layer prefixes)
   - Cross-layer communication via locals
   - Setup script patterns and logging conventions
   - Testing requirements (unit, tofu, integration)

2. Ask me for the following information:
   - Layer type (provider, network, or distribution)
   - Provider/service name (e.g., Cloudflare, Netlify, DigitalOcean)
   - Required environment variables or context values to validate
   - External APIs to call (if any)
   - Terraform resources to create
   - Cross-layer dependencies and exports

3. After gathering requirements, generate:
   - Setup script with validation and TOFU_VARIABLES
   - Terraform module (main.tf, variables.tf, locals.tf, outputs.tf, test_locals.tf)
   - Unit tests (BATS) for the setup script
   - Tofu tests for the Terraform module
   - Integration test additions (if applicable)

**Reference Files by Layer Type:**

For PROVIDER layers, reference:
- Setup script: `frontend/deployment/provider/azure/setup`
- Terraform module: `frontend/deployment/provider/azure/modules/`
- Unit test (BATS): `frontend/deployment/tests/provider/azure/setup_test.bats`
- Tofu test: `frontend/deployment/provider/azure/modules/provider.tftest.hcl`

For NETWORK layers, reference:
- Setup script: `frontend/deployment/network/azure_dns/setup`
- Terraform module: `frontend/deployment/network/azure_dns/modules/`
- Unit test (BATS): `frontend/deployment/tests/network/azure_dns/setup_test.bats`
- Tofu test: `frontend/deployment/network/azure_dns/modules/azure_dns.tftest.hcl`

For DISTRIBUTION layers, reference:
- Setup script: `frontend/deployment/distribution/blob-cdn/setup`
- Terraform module: `frontend/deployment/distribution/blob-cdn/modules/`
- Unit test (BATS): `frontend/deployment/tests/distribution/blob-cdn/setup_test.bats`
- Tofu test: `frontend/deployment/distribution/blob-cdn/modules/blob-cdn.tftest.hcl`

For INTEGRATION tests, reference:
- `frontend/deployment/tests/integration/test_cases/azure_blobcdn_azuredns/lifecycle_test.bats`
````

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Variable not found" | Missing setup script execution | Ensure workflow runs all setup scripts in order |
| "Local not found" | Missing cross-layer local | Add to `locals.tf` or check `test_locals.tf` for unit tests |
| "Module not composed" | `MODULES_TO_USE` not updated | Verify setup script appends to `MODULES_TO_USE` |
| "Backend not configured" | Missing provider setup | Run provider layer setup first |

### Debug Commands

```bash
# Check composed modules
echo $MODULES_TO_USE

# Check TOFU_VARIABLES
echo $TOFU_VARIABLES | jq .

# Validate terraform
cd /path/to/composed/modules && tofu validate
```
