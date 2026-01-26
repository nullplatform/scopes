# =============================================================================
# Unit tests for network/azure_dns module
#
# Run: tofu test
# =============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-resource-group/providers/Microsoft.Network/dnszones/example.com"
    }
  }
}

variables {
  network_dns_zone_name = "example.com"
  network_domain        = "example.com"
  network_subdomain     = "app"

  azure_provider = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = "my-resource-group"
    storage_account = "mytfstatestorage"
    container       = "tfstate"
  }

  # These come from the distribution module (e.g., blob-cdn)
  distribution_target_domain = "myapp.azureedge.net"
  distribution_record_type   = "CNAME"
}

# =============================================================================
# Test: Full domain is computed correctly with subdomain
# =============================================================================
run "full_domain_with_subdomain" {
  command = plan

  assert {
    condition     = local.network_full_domain == "app.example.com"
    error_message = "Full domain should be 'app.example.com', got '${local.network_full_domain}'"
  }
}

# =============================================================================
# Test: Full domain is computed correctly without subdomain (apex)
# =============================================================================
run "full_domain_apex" {
  command = plan

  variables {
    network_subdomain = ""
  }

  assert {
    condition     = local.network_full_domain == "example.com"
    error_message = "Full domain should be 'example.com' for apex, got '${local.network_full_domain}'"
  }
}

# =============================================================================
# Test: CNAME record is created for CNAME type
# =============================================================================
run "creates_cname_record_for_type_cname" {
  command = plan

  variables {
    distribution_record_type = "CNAME"
  }

  assert {
    condition     = length(azurerm_dns_cname_record.main) == 1
    error_message = "Should create one CNAME record"
  }

  assert {
    condition     = length(azurerm_dns_a_record.main) == 0
    error_message = "Should not create A record when type is CNAME"
  }
}

# =============================================================================
# Test: A record is created for A type
# =============================================================================
run "creates_a_record_for_type_a" {
  command = plan

  variables {
    distribution_record_type = "A"
  }

  assert {
    condition     = length(azurerm_dns_a_record.main) == 1
    error_message = "Should create one A record"
  }

  assert {
    condition     = length(azurerm_dns_cname_record.main) == 0
    error_message = "Should not create CNAME record when type is A"
  }
}

# =============================================================================
# Test: CNAME record configuration
# =============================================================================
run "cname_record_configuration" {
  command = plan

  variables {
    distribution_record_type = "CNAME"
  }

  assert {
    condition     = azurerm_dns_cname_record.main[0].zone_name == "example.com"
    error_message = "CNAME record should use the correct DNS zone"
  }

  assert {
    condition     = azurerm_dns_cname_record.main[0].name == "app"
    error_message = "CNAME record name should be the subdomain"
  }

  assert {
    condition     = azurerm_dns_cname_record.main[0].ttl == 300
    error_message = "CNAME TTL should be 300"
  }

  assert {
    condition     = azurerm_dns_cname_record.main[0].record == "myapp.azureedge.net"
    error_message = "CNAME record should point to distribution target domain"
  }

  assert {
    condition     = azurerm_dns_cname_record.main[0].resource_group_name == "my-resource-group"
    error_message = "CNAME record should be in the correct resource group"
  }
}

# =============================================================================
# Test: A record configuration
# =============================================================================
run "a_record_configuration" {
  command = plan

  variables {
    distribution_record_type   = "A"
    distribution_target_domain = "10.0.0.1"
  }

  assert {
    condition     = azurerm_dns_a_record.main[0].zone_name == "example.com"
    error_message = "A record should use the correct DNS zone"
  }

  assert {
    condition     = azurerm_dns_a_record.main[0].name == "app"
    error_message = "A record name should be the subdomain"
  }

  assert {
    condition     = azurerm_dns_a_record.main[0].ttl == 300
    error_message = "A record TTL should be 300"
  }

  assert {
    condition     = azurerm_dns_a_record.main[0].resource_group_name == "my-resource-group"
    error_message = "A record should be in the correct resource group"
  }
}

# =============================================================================
# Test: Outputs
# =============================================================================
run "outputs_are_correct" {
  command = plan

  assert {
    condition     = output.network_full_domain == "app.example.com"
    error_message = "network_full_domain output should be 'app.example.com'"
  }

  assert {
    condition     = output.network_website_url == "https://app.example.com"
    error_message = "network_website_url output should be 'https://app.example.com'"
  }
}

# =============================================================================
# Test: DNS zone variable is correctly passed
# =============================================================================
run "dns_zone_variable_configuration" {
  command = plan

  assert {
    condition     = var.network_dns_zone_name == "example.com"
    error_message = "DNS zone name variable should be 'example.com'"
  }
}
