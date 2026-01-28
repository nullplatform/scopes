# =============================================================================
# Azure Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.4.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    # Backend configuration is provided via -backend-config flags:
    # - storage_account_name
    # - container_name
    # - resource_group_name
    # - key (provided by build_context)
  }
}

provider "azurerm" {
  features {}

  subscription_id = var.azure_provider.subscription_id

  default_tags {
    tags = var.provider_resource_tags_json
  }
}
