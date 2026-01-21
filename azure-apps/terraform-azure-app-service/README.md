# Azure App Service Terraform Module

This Terraform module provisions an Azure App Service with:
- Docker container support
- Custom domain with DNS A record
- Free managed SSL certificate
- Deployment slots for blue-green / canary deployments
- Environment variables from JSON configuration

## Architecture

```
                                    ┌─────────────────────────────────────────┐
                                    │           Azure DNS Zone                │
                                    │         (example.com)                   │
                                    └──────────────┬──────────────────────────┘
                                                   │
                                    ┌──────────────▼──────────────┐
                                    │    A Record / CNAME         │
                                    │   api.example.com           │
                                    └──────────────┬──────────────┘
                                                   │
                                    ┌──────────────▼──────────────┐
                                    │   Custom Domain Binding     │
                                    │   + Managed SSL Cert        │
                                    └──────────────┬──────────────┘
                                                   │
                         ┌─────────────────────────┴─────────────────────────┐
                         │                                                   │
              ┌──────────▼──────────┐                         ┌──────────────▼──────────┐
              │   Production Slot   │ ◄───── Traffic ───────► │     Staging Slot        │
              │   (90% traffic)     │        Splitting        │     (10% traffic)       │
              │                     │                         │                         │
              │  ┌───────────────┐  │                         │  ┌───────────────┐      │
              │  │ Docker Image  │  │                         │  │ Docker Image  │      │
              │  │ myapp:v1.0.0  │  │                         │  │ myapp:v1.1.0  │      │
              │  └───────────────┘  │                         │  └───────────────┘      │
              └─────────────────────┘                         └─────────────────────────┘
                         │                                                   │
                         └─────────────────────────┬─────────────────────────┘
                                                   │
                                    ┌──────────────▼──────────────┐
                                    │     App Service Plan        │
                                    │     (S1 - Standard)         │
                                    └─────────────────────────────┘
```

## Prerequisites

1. Azure CLI installed and authenticated (`az login`)
2. Terraform >= 1.0
3. An existing Azure Resource Group
4. An existing Azure DNS Zone (or you can modify to create one)
5. Docker images pushed to a container registry (ACR, Docker Hub, etc.)

## Quick Start

### 1. Clone and configure

```bash
# Copy the example tfvars
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 2. Set sensitive variables via environment

```bash
# For Azure Container Registry
export TF_VAR_docker_registry_username="your-acr-username"
export TF_VAR_docker_registry_password="your-acr-password"

# Or use Azure managed identity (recommended for ACR)
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Variables

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `resource_group_name` | Name of the resource group | string | yes |
| `app_name` | Globally unique name for the App Service | string | yes |
| `docker_image` | Docker image with tag (e.g., `myapp:v1.0.0`) | string | yes |
| `dns_zone_name` | Azure DNS zone name | string | yes |
| `dns_zone_resource_group` | Resource group containing DNS zone | string | yes |
| `resource_tags` | Tags to apply to resources | map(string) | no |
| `parameter_json` | JSON string with environment variables | string | no |
| `custom_subdomain` | Subdomain (use `@` for apex) | string | no |
| `docker_registry_url` | Registry URL | string | no |
| `sku_name` | App Service Plan SKU | string | no |
| `enable_staging_slot` | Create staging slot | bool | no |

## Environment Variables (parameter_json)

Pass environment variables as a JSON string:

```hcl
parameter_json = <<EOF
{
  "DATABASE_URL": "postgresql://...",
  "REDIS_URL": "redis://...",
  "API_KEY": "secret-key",
  "LOG_LEVEL": "info"
}
EOF
```

Or from a file:

```hcl
parameter_json = file("${path.module}/env.json")
```

## Traffic Management (Canary Deployments)

### Using the script

```bash
# Make executable
chmod +x scripts/traffic-management.sh

# Check current status
./scripts/traffic-management.sh my-app-rg my-awesome-app status

# Route 10% to staging (canary)
./scripts/traffic-management.sh my-app-rg my-awesome-app 10

# Increase to 50%
./scripts/traffic-management.sh my-app-rg my-awesome-app 50

# Full rollout - swap slots
./scripts/traffic-management.sh my-app-rg my-awesome-app swap

# Rollback - swap back
./scripts/traffic-management.sh my-app-rg my-awesome-app swap
```

### Canary Deployment Workflow

```
1. Deploy new version to STAGING slot
   └── terraform apply (update docker_image in staging)

2. Test staging directly
   └── https://my-awesome-app-staging.azurewebsites.net

3. Gradual traffic shift
   └── 5% → 10% → 25% → 50% → 100%

4. Monitor metrics at each step
   └── Check error rates, latency, logs

5. If issues: rollback to 0%
   └── ./traffic-management.sh my-rg my-app 0

6. If successful: swap slots
   └── ./traffic-management.sh my-rg my-app swap
```

## Updating Docker Image

### Update production

```hcl
# In terraform.tfvars
docker_image = "myapp:v1.1.0"
```

```bash
terraform apply
```

### Update staging only (for canary)

Modify the staging slot resource directly or use Azure CLI:

```bash
az webapp config container set \
  --resource-group my-app-rg \
  --name my-awesome-app \
  --slot staging \
  --docker-custom-image-name myapp:v1.1.0
```

## Outputs

| Name | Description |
|------|-------------|
| `app_service_default_hostname` | Default Azure hostname |
| `app_service_custom_domain` | Your custom domain |
| `staging_slot_url` | Staging slot URL |
| `app_service_outbound_ips` | IPs for firewall rules |

## Using with Azure Container Registry (ACR)

```hcl
docker_registry_url      = "https://myregistry.azurecr.io"
docker_image             = "myregistry.azurecr.io/myapp:v1.0.0"
docker_registry_username = "myregistry"  # Or use managed identity
docker_registry_password = "access-key"
```

### Better: Use Managed Identity

```hcl
# Add to main.tf
resource "azurerm_role_assignment" "acr_pull" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}
```

## Common Issues

### DNS propagation delay

Custom domain binding may fail if DNS hasn't propagated. Wait a few minutes and retry.

### Certificate provisioning

Free managed certificates can take 10-15 minutes to provision after domain binding.

### Slot swap issues

Ensure both slots have the same app settings structure. Use `sticky_settings` for slot-specific values.

## CI/CD Integration

See the `examples/` directory for:
- GitHub Actions workflow
- Azure DevOps pipeline
- GitLab CI configuration
