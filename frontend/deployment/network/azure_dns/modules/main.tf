# Azure DNS Configuration
# Creates DNS records pointing to hosting resources (CDN, Static Web Apps, etc.)

variable "network_resource_group" {
  description = "Resource group containing the DNS zone"
  type        = string
}

variable "network_zone_name" {
  description = "Azure DNS zone name"
  type        = string
}

variable "network_domain" {
  description = "Domain/subdomain for the application"
  type        = string
}

variable "network_target_domain" {
  description = "Target domain (for CNAME records)"
  type        = string
}

variable "network_ttl" {
  description = "DNS record TTL in seconds"
  type        = number
  default     = 300
}

variable "network_create_www" {
  description = "Create www subdomain record as well"
  type        = bool
  default     = true
}

variable "network_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

# CNAME record for main domain
resource "azurerm_dns_cname_record" "main" {
  name                = var.network_domain == var.network_zone_name ? "@" : replace(var.network_domain, ".${var.network_zone_name}", "")
  zone_name           = var.network_zone_name
  resource_group_name = var.network_resource_group
  ttl                 = var.network_ttl
  record              = var.network_target_domain

  tags = var.network_tags
}

# WWW subdomain
resource "azurerm_dns_cname_record" "www" {
  count = var.network_create_www ? 1 : 0

  name                = "www"
  zone_name           = var.network_zone_name
  resource_group_name = var.network_resource_group
  ttl                 = var.network_ttl
  record              = var.network_target_domain

  tags = var.network_tags
}

output "network_domain" {
  description = "Configured domain"
  value       = var.network_domain
}

output "network_fqdn" {
  description = "Fully qualified domain name"
  value       = azurerm_dns_cname_record.main.fqdn
}

output "network_website_url" {
  description = "Website URL"
  value       = "https://${var.network_domain}"
}
