# Azure Blob Storage + CDN Hosting
# Resources for Azure static hosting with CDN

variable "hosting_app_name" {
  description = "Application name"
  type        = string
}

variable "hosting_environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "hosting_location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "hosting_custom_domain" {
  description = "Custom domain (e.g., app.example.com)"
  type        = string
  default     = null
}

variable "hosting_cdn_sku" {
  description = "CDN Profile SKU"
  type        = string
  default     = "Standard_Microsoft"
}

variable "hosting_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

locals {
  hosting_storage_account_name = lower(replace("${var.hosting_app_name}${var.hosting_environment}static", "-", ""))

  hosting_default_tags = merge(var.hosting_tags, {
    Application = var.hosting_app_name
    Environment = var.hosting_environment
    ManagedBy   = "terraform"
  })
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.hosting_app_name}-${var.hosting_environment}"
  location = var.hosting_location
  tags     = local.hosting_default_tags
}

resource "azurerm_storage_account" "static" {
  name                     = substr(local.hosting_storage_account_name, 0, 24)
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  static_website {
    index_document     = "index.html"
    error_404_document = "index.html"
  }

  min_tls_version                 = "TLS1_2"
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "OPTIONS"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
  }

  tags = local.hosting_default_tags
}

resource "azurerm_cdn_profile" "main" {
  name                = "cdn-${var.hosting_app_name}-${var.hosting_environment}"
  location            = "global"
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.hosting_cdn_sku
  tags                = local.hosting_default_tags
}

resource "azurerm_cdn_endpoint" "static" {
  name                = "${var.hosting_app_name}-${var.hosting_environment}"
  profile_name        = azurerm_cdn_profile.main.name
  location            = "global"
  resource_group_name = azurerm_resource_group.main.name

  origin {
    name      = "static-website"
    host_name = azurerm_storage_account.static.primary_web_host
  }

  origin_host_header = azurerm_storage_account.static.primary_web_host

  is_compression_enabled = true
  content_types_to_compress = [
    "application/javascript",
    "application/json",
    "application/xml",
    "text/css",
    "text/html",
    "text/javascript",
    "text/plain",
    "text/xml",
    "image/svg+xml"
  ]

  querystring_caching_behaviour = "IgnoreQueryString"

  tags = local.hosting_default_tags
}

resource "azurerm_cdn_endpoint_custom_domain" "main" {
  count = var.hosting_custom_domain != null ? 1 : 0

  name            = replace(var.hosting_custom_domain, ".", "-")
  cdn_endpoint_id = azurerm_cdn_endpoint.static.id
  host_name       = var.hosting_custom_domain

  cdn_managed_https {
    certificate_type = "Dedicated"
    protocol_type    = "ServerNameIndication"
    tls_version      = "TLS12"
  }
}

output "hosting_resource_group_name" {
  description = "Resource Group name"
  value       = azurerm_resource_group.main.name
}

output "hosting_storage_account_name" {
  description = "Storage Account name"
  value       = azurerm_storage_account.static.name
}

output "hosting_cdn_endpoint_hostname" {
  description = "CDN Endpoint hostname"
  value       = azurerm_cdn_endpoint.static.fqdn
}

output "hosting_website_url" {
  description = "Website URL"
  value       = var.hosting_custom_domain != null ? "https://${var.hosting_custom_domain}" : "https://${azurerm_cdn_endpoint.static.fqdn}"
}

output "hosting_upload_command" {
  description = "Command to upload files"
  value       = "az storage blob upload-batch --account-name ${azurerm_storage_account.static.name} --destination '$web' --source ./dist"
}
