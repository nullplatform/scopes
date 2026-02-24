# =============================================================================
# Azure CDN Distribution
#
# Creates an Azure CDN profile and endpoint for static website hosting
# using Azure Blob Storage as the origin.
# =============================================================================

# Get storage account details
data "azurerm_storage_account" "static" {
  name                = var.distribution_storage_account
  resource_group_name = var.azure_provider.resource_group
}

# CDN Profile
resource "azurerm_cdn_profile" "static" {
  name                = "${var.distribution_app_name}-cdn"
  location            = "global"
  resource_group_name = var.azure_provider.resource_group
  sku                 = "Standard_Microsoft"

  tags = local.distribution_tags
}

# CDN Endpoint
resource "azurerm_cdn_endpoint" "static" {
  name                = var.distribution_app_name
  profile_name        = azurerm_cdn_profile.static.name
  location            = "global"
  resource_group_name = var.azure_provider.resource_group

  origin_host_header = data.azurerm_storage_account.static.primary_web_host

  origin {
    name      = "blob-origin"
    host_name = data.azurerm_storage_account.static.primary_web_host
  }

  # SPA routing - redirect 404s to index.html
  delivery_rule {
    name  = "sparouting"
    order = 1

    url_file_extension_condition {
      operator     = "LessThan"
      match_values = ["1"]
    }

    url_rewrite_action {
      destination             = "/index.html"
      preserve_unmatched_path = false
      source_pattern          = "/"
    }
  }

  # Cache configuration
  delivery_rule {
    name  = "staticcache"
    order = 2

    url_path_condition {
      operator     = "BeginsWith"
      match_values = ["/static/"]
    }

    cache_expiration_action {
      behavior = "Override"
      duration = "7.00:00:00"
    }
  }

  # HTTPS redirect
  delivery_rule {
    name  = "httpsredirect"
    order = 3

    request_scheme_condition {
      operator     = "Equal"
      match_values = ["HTTP"]
    }

    url_redirect_action {
      redirect_type = "Found"
      protocol      = "Https"
    }
  }

  tags = local.distribution_tags
}

# Custom domain configuration (when network layer provides domain)
resource "azurerm_cdn_endpoint_custom_domain" "static" {
  count = local.distribution_has_custom_domain ? 1 : 0

  name            = "custom-domain"
  cdn_endpoint_id = azurerm_cdn_endpoint.static.id
  host_name       = local.distribution_full_domain

  cdn_managed_https {
    certificate_type = "Dedicated"
    protocol_type    = "ServerNameIndication"
    tls_version      = "TLS12"
  }
}
