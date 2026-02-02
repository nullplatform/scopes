# =============================================================================
# Unit tests for distribution/blob-cdn module
#
# Run: tofu test
# =============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_storage_account" {
    defaults = {
      primary_web_host = "mystaticstorage.z13.web.core.windows.net"
    }
  }

  mock_resource "azurerm_cdn_endpoint" {
    defaults = {
      id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-resource-group/providers/Microsoft.Cdn/profiles/my-app-prod-cdn/endpoints/my-app-prod"
      fqdn = "my-app-prod.azureedge.net"
    }
  }
}

variables {
  distribution_storage_account    = "mystaticstorage"
  distribution_container_name     = "$web"
  distribution_blob_prefix        = "app/scope-1"
  distribution_app_name           = "my-app-prod"
  network_full_domain             = ""
  network_domain                  = ""
  distribution_resource_tags_json = {
    Environment = "production"
    Application = "my-app"
  }
  azure_provider = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = "my-resource-group"
    storage_account = "mytfstatestorage"
    container       = "tfstate"
  }
  provider_resource_tags_json = {
    Team = "platform"
  }
}

# =============================================================================
# Test: CDN Profile is created
# =============================================================================
run "creates_cdn_profile" {
  command = plan

  assert {
    condition     = azurerm_cdn_profile.static.name == "my-app-prod-cdn"
    error_message = "CDN profile name should be 'my-app-prod-cdn'"
  }

  assert {
    condition     = azurerm_cdn_profile.static.sku == "Standard_Microsoft"
    error_message = "CDN profile SKU should be 'Standard_Microsoft'"
  }

  assert {
    condition     = azurerm_cdn_profile.static.resource_group_name == "my-resource-group"
    error_message = "CDN profile should be in 'my-resource-group'"
  }
}

# =============================================================================
# Test: CDN Endpoint is created
# =============================================================================
run "creates_cdn_endpoint" {
  command = plan

  assert {
    condition     = azurerm_cdn_endpoint.static.name == "my-app-prod"
    error_message = "CDN endpoint name should be 'my-app-prod'"
  }

  assert {
    condition     = azurerm_cdn_endpoint.static.profile_name == "my-app-prod-cdn"
    error_message = "CDN endpoint profile should be 'my-app-prod-cdn'"
  }
}

# =============================================================================
# Test: CDN Endpoint origin configuration
# =============================================================================
run "cdn_endpoint_origin_configuration" {
  command = plan

  assert {
    condition     = azurerm_cdn_endpoint.static.origin_host_header == "mystaticstorage.z13.web.core.windows.net"
    error_message = "Origin host header should be storage account primary web host"
  }

  assert {
    condition     = one(azurerm_cdn_endpoint.static.origin).name == "blob-origin"
    error_message = "Origin name should be 'blob-origin'"
  }

  assert {
    condition     = one(azurerm_cdn_endpoint.static.origin).host_name == "mystaticstorage.z13.web.core.windows.net"
    error_message = "Origin host name should be storage account primary web host"
  }
}

# =============================================================================
# Test: No custom domain without network_full_domain
# =============================================================================
run "no_custom_domain_without_network_domain" {
  command = plan

  assert {
    condition     = local.distribution_has_custom_domain == false
    error_message = "Should not have custom domain when network_full_domain is empty"
  }

  assert {
    condition     = length(azurerm_cdn_endpoint_custom_domain.static) == 0
    error_message = "Should not create custom domain resource when network_full_domain is empty"
  }
}

# =============================================================================
# Test: Custom domain with network_full_domain
# =============================================================================
run "has_custom_domain_with_network_domain" {
  command = plan

  variables {
    network_full_domain = "cdn.example.com"
  }

  assert {
    condition     = local.distribution_has_custom_domain == true
    error_message = "Should have custom domain when network_full_domain is set"
  }

  assert {
    condition     = local.distribution_full_domain == "cdn.example.com"
    error_message = "Full domain should be 'cdn.example.com'"
  }

  assert {
    condition     = length(azurerm_cdn_endpoint_custom_domain.static) == 1
    error_message = "Should create custom domain resource when network_full_domain is set"
  }

  assert {
    condition     = azurerm_cdn_endpoint_custom_domain.static[0].host_name == "cdn.example.com"
    error_message = "Custom domain host name should be 'cdn.example.com'"
  }
}

# =============================================================================
# Test: Origin path normalization - removes double slashes
# =============================================================================
run "origin_path_normalizes_leading_slash" {
  command = plan

  variables {
    distribution_blob_prefix = "/app"
  }

  assert {
    condition     = local.distribution_origin_path == "/app"
    error_message = "Origin path should be '/app' not '//app'"
  }
}

# =============================================================================
# Test: Origin path normalization - adds leading slash if missing
# =============================================================================
run "origin_path_adds_leading_slash" {
  command = plan

  variables {
    distribution_blob_prefix = "app"
  }

  assert {
    condition     = local.distribution_origin_path == "/app"
    error_message = "Origin path should add leading slash"
  }
}

# =============================================================================
# Test: Origin path normalization - handles empty prefix
# =============================================================================
run "origin_path_handles_empty" {
  command = plan

  variables {
    distribution_blob_prefix = ""
  }

  assert {
    condition     = local.distribution_origin_path == ""
    error_message = "Origin path should be empty when prefix is empty"
  }
}

# =============================================================================
# Test: Origin path normalization - trims trailing slashes
# =============================================================================
run "origin_path_trims_trailing_slash" {
  command = plan

  variables {
    distribution_blob_prefix = "/app/subfolder/"
  }

  assert {
    condition     = local.distribution_origin_path == "/app/subfolder"
    error_message = "Origin path should trim trailing slashes"
  }
}

# =============================================================================
# Test: Cross-module locals for DNS integration
# =============================================================================
run "cross_module_locals_for_dns" {
  command = plan

  assert {
    condition     = local.distribution_record_type == "CNAME"
    error_message = "Record type should be 'CNAME' for Azure CDN records"
  }
}

# =============================================================================
# Test: Outputs from data source
# =============================================================================
run "outputs_from_data_source" {
  command = plan

  assert {
    condition     = output.distribution_storage_account == "mystaticstorage"
    error_message = "distribution_storage_account should be 'mystaticstorage'"
  }
}

# =============================================================================
# Test: Outputs from variables
# =============================================================================
run "outputs_from_variables" {
  command = plan

  assert {
    condition     = output.distribution_blob_prefix == "app/scope-1"
    error_message = "distribution_blob_prefix should be 'app/scope-1'"
  }

  assert {
    condition     = output.distribution_container_name == "$web"
    error_message = "distribution_container_name should be '$web'"
  }
}

# =============================================================================
# Test: DNS-related outputs
# =============================================================================
run "dns_related_outputs" {
  command = plan

  assert {
    condition     = output.distribution_record_type == "CNAME"
    error_message = "distribution_record_type should be 'CNAME'"
  }
}

# =============================================================================
# Test: Website URL without network domain
# =============================================================================
run "website_url_without_network_domain" {
  command = plan

  assert {
    condition     = startswith(output.distribution_website_url, "https://")
    error_message = "distribution_website_url should start with 'https://'"
  }
}

# =============================================================================
# Test: Website URL with network domain
# =============================================================================
run "website_url_with_network_domain" {
  command = plan

  variables {
    network_full_domain = "cdn.example.com"
  }

  assert {
    condition     = output.distribution_website_url == "https://cdn.example.com"
  error_message = "distribution_website_url should be 'https://cdn.example.com'"
  }
}

# =============================================================================
# Test: CDN endpoint has SPA routing delivery rule
# =============================================================================
run "cdn_endpoint_has_spa_routing" {
  command = plan

  assert {
    condition     = azurerm_cdn_endpoint.static.delivery_rule[0].name == "sparouting"
    error_message = "Should have sparouting delivery rule"
  }

  assert {
    condition     = azurerm_cdn_endpoint.static.delivery_rule[0].order == 1
    error_message = "SPA routing rule should have order 1"
  }
}

# =============================================================================
# Test: CDN endpoint has static cache delivery rule
# =============================================================================
run "cdn_endpoint_has_static_cache" {
  command = plan

  assert {
    condition     = azurerm_cdn_endpoint.static.delivery_rule[1].name == "staticcache"
    error_message = "Should have staticcache delivery rule"
  }

  assert {
    condition     = azurerm_cdn_endpoint.static.delivery_rule[1].order == 2
    error_message = "Static cache rule should have order 2"
  }
}

# =============================================================================
# Test: CDN endpoint has HTTPS redirect delivery rule
# =============================================================================
run "cdn_endpoint_has_https_redirect" {
  command = plan

  assert {
    condition     = azurerm_cdn_endpoint.static.delivery_rule[2].name == "httpsredirect"
    error_message = "Should have httpsredirect delivery rule"
  }

  assert {
    condition     = azurerm_cdn_endpoint.static.delivery_rule[2].order == 3
    error_message = "HTTPS redirect rule should have order 3"
  }
}

# =============================================================================
# Test: Custom domain has managed HTTPS
# =============================================================================
run "custom_domain_has_managed_https" {
  command = plan

  variables {
    network_full_domain = "cdn.example.com"
  }

  assert {
    condition     = azurerm_cdn_endpoint_custom_domain.static[0].cdn_managed_https[0].certificate_type == "Dedicated"
    error_message = "Custom domain should use dedicated certificate"
  }

  assert {
    condition     = azurerm_cdn_endpoint_custom_domain.static[0].cdn_managed_https[0].protocol_type == "ServerNameIndication"
    error_message = "Custom domain should use SNI protocol"
  }

  assert {
    condition     = azurerm_cdn_endpoint_custom_domain.static[0].cdn_managed_https[0].tls_version == "TLS12"
    error_message = "Custom domain should use TLS 1.2"
  }
}
