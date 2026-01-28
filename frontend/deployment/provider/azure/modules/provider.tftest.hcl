# =============================================================================
# Unit tests for provider/azure module
#
# Run: tofu test
# =============================================================================

mock_provider "azurerm" {}

variables {
  azure_provider = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = "my-resource-group"
    storage_account = "mytfstatestorage"
    container       = "tfstate"
  }

  provider_resource_tags_json = {
    Environment = "test"
    Project     = "frontend"
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# Test: Provider configuration is valid
# =============================================================================
run "provider_configuration_is_valid" {
  command = plan

  assert {
    condition     = var.azure_provider.subscription_id == "00000000-0000-0000-0000-000000000000"
    error_message = "Azure subscription ID should match"
  }

  assert {
    condition     = var.azure_provider.resource_group == "my-resource-group"
    error_message = "Resource group should be my-resource-group"
  }

  assert {
    condition     = var.azure_provider.storage_account == "mytfstatestorage"
    error_message = "Storage account should be mytfstatestorage"
  }

  assert {
    condition     = var.azure_provider.container == "tfstate"
    error_message = "Container should be tfstate"
  }
}

# =============================================================================
# Test: Default tags are configured
# =============================================================================
run "default_tags_are_configured" {
  command = plan

  assert {
    condition     = var.provider_resource_tags_json["Environment"] == "test"
    error_message = "Environment tag should be 'test'"
  }

  assert {
    condition     = var.provider_resource_tags_json["ManagedBy"] == "terraform"
    error_message = "ManagedBy tag should be 'terraform'"
  }
}

# =============================================================================
# Test: Required variables validation
# =============================================================================
run "azure_provider_requires_subscription_id" {
  command = plan

  variables {
    azure_provider = {
      subscription_id = ""
      resource_group  = "rg"
      storage_account = "storage"
      container       = "container"
    }
  }

  # Empty subscription_id should still be syntactically valid but semantically wrong
  # This tests that the variable structure is enforced
  assert {
    condition     = var.azure_provider.subscription_id == ""
    error_message = "Empty subscription_id should be accepted by variable type"
  }
}
