
# Azure Static Web Apps Hosting
# Resources for Azure Static Web Apps

variable "distribution_app_name" {
  description = "Application name"
  type        = string
}

variable "distribution_environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "distribution_location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "distribution_sku_tier" {
  description = "SKU tier (Free or Standard)"
  type        = string
  default     = "Free"
}

variable "distribution_sku_size" {
  description = "SKU size"
  type        = string
  default     = "Free"
}

variable "distribution_custom_domains" {
  description = "List of custom domains"
  type        = list(string)
  default     = []
}

variable "distribution_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

locals {
  distribution_default_tags = merge(var.distribution_tags, {
    Application = var.distribution_app_name
    Environment = var.distribution_environment
    ManagedBy   = "terraform"
  })
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.distribution_app_name}-${var.distribution_environment}"
  location = var.distribution_location
  tags     = local.distribution_default_tags
}

resource "azurerm_static_web_app" "main" {
  name                = "swa-${var.distribution_app_name}-${var.distribution_environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.distribution_location

  sku_tier = var.distribution_sku_tier
  sku_size = var.distribution_sku_size

  tags = local.distribution_default_tags
}

resource "azurerm_static_web_app_custom_domain" "main" {
  for_each = toset(var.distribution_custom_domains)

  static_web_app_id = azurerm_static_web_app.main.id
  domain_name       = each.value
  validation_type   = "cname-delegation"
}

output "distribution_resource_group_name" {
  description = "Resource Group name"
  value       = azurerm_resource_group.main.name
}

output "distribution_static_web_app_id" {
  description = "Static Web App ID"
  value       = azurerm_static_web_app.main.id
}

output "distribution_static_web_app_name" {
  description = "Static Web App name"
  value       = azurerm_static_web_app.main.name
}

output "distribution_default_hostname" {
  description = "Default hostname"
  value       = azurerm_static_web_app.main.default_host_name
}

output "distribution_website_url" {
  description = "Website URL"
  value       = length(var.distribution_custom_domains) > 0 ? "https://${var.distribution_custom_domains[0]}" : "https://${azurerm_static_web_app.main.default_host_name}"
}

output "distribution_api_key" {
  description = "API key for deployments"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}
