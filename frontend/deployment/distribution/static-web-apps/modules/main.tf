# Azure Static Web Apps Hosting
# Resources for Azure Static Web Apps

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

variable "hosting_sku_tier" {
  description = "SKU tier (Free or Standard)"
  type        = string
  default     = "Free"
}

variable "hosting_sku_size" {
  description = "SKU size"
  type        = string
  default     = "Free"
}

variable "hosting_custom_domains" {
  description = "List of custom domains"
  type        = list(string)
  default     = []
}

variable "hosting_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

locals {
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

resource "azurerm_static_web_app" "main" {
  name                = "swa-${var.hosting_app_name}-${var.hosting_environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.hosting_location

  sku_tier = var.hosting_sku_tier
  sku_size = var.hosting_sku_size

  tags = local.hosting_default_tags
}

resource "azurerm_static_web_app_custom_domain" "main" {
  for_each = toset(var.hosting_custom_domains)

  static_web_app_id = azurerm_static_web_app.main.id
  domain_name       = each.value
  validation_type   = "cname-delegation"
}

output "hosting_resource_group_name" {
  description = "Resource Group name"
  value       = azurerm_resource_group.main.name
}

output "hosting_static_web_app_id" {
  description = "Static Web App ID"
  value       = azurerm_static_web_app.main.id
}

output "hosting_static_web_app_name" {
  description = "Static Web App name"
  value       = azurerm_static_web_app.main.name
}

output "hosting_default_hostname" {
  description = "Default hostname"
  value       = azurerm_static_web_app.main.default_host_name
}

output "hosting_website_url" {
  description = "Website URL"
  value       = length(var.hosting_custom_domains) > 0 ? "https://${var.hosting_custom_domains[0]}" : "https://${azurerm_static_web_app.main.default_host_name}"
}

output "hosting_api_key" {
  description = "API key for deployments"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}
