# =============================================================================
# Azure DNS Network
#
# Creates DNS records in Azure DNS zone for the distribution endpoint.
# Supports both CNAME records (for CDN endpoints) and A records (for static IPs).
# =============================================================================

# Get DNS zone details
data "azurerm_dns_zone" "main" {
  name                = var.network_dns_zone_name
  resource_group_name = var.azure_provider.resource_group
}

# CNAME record for CDN endpoints
resource "azurerm_dns_cname_record" "main" {
  count = local.distribution_record_type == "CNAME" ? 1 : 0

  name                = var.network_subdomain
  zone_name           = var.network_dns_zone_name
  resource_group_name = var.azure_provider.resource_group
  ttl                 = 300
  record              = local.distribution_target_domain
}

# A record for static IPs (if needed in the future)
resource "azurerm_dns_a_record" "main" {
  count = local.distribution_record_type == "A" ? 1 : 0

  name                = var.network_subdomain
  zone_name           = var.network_dns_zone_name
  resource_group_name = var.azure_provider.resource_group
  ttl                 = 300
  records             = [local.distribution_target_domain]
}