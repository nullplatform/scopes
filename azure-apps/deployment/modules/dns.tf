# =============================================================================
# DNS / CUSTOM DOMAIN
# =============================================================================

# Reference existing DNS zone
data "azurerm_dns_zone" "main" {
  count               = var.enable_custom_domain ? 1 : 0
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group
}

# ---------------------------------------------------------------------------
# A RECORD (for apex domain)
# ---------------------------------------------------------------------------
resource "azurerm_dns_a_record" "main" {
  count               = var.enable_custom_domain && var.custom_subdomain == "@" ? 1 : 0
  name                = "@"
  zone_name           = data.azurerm_dns_zone.main[0].name
  resource_group_name = var.dns_zone_resource_group
  ttl                 = 300
  target_resource_id  = azurerm_linux_web_app.main.id

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# CNAME RECORD (for subdomains)
# ---------------------------------------------------------------------------
resource "azurerm_dns_cname_record" "main" {
  count               = var.enable_custom_domain && var.custom_subdomain != "@" ? 1 : 0
  name                = var.custom_subdomain
  zone_name           = data.azurerm_dns_zone.main[0].name
  resource_group_name = var.dns_zone_resource_group
  ttl                 = 300
  record              = azurerm_linux_web_app.main.default_hostname

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# TXT RECORD (for domain verification)
# ---------------------------------------------------------------------------
resource "azurerm_dns_txt_record" "verification" {
  count               = var.enable_custom_domain ? 1 : 0
  name                = var.custom_subdomain == "@" ? "asuid" : "asuid.${var.custom_subdomain}"
  zone_name           = data.azurerm_dns_zone.main[0].name
  resource_group_name = var.dns_zone_resource_group
  ttl                 = 300

  record {
    value = azurerm_linux_web_app.main.custom_domain_verification_id
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# CUSTOM DOMAIN BINDING
# ---------------------------------------------------------------------------
resource "azurerm_app_service_custom_hostname_binding" "main" {
  count               = var.enable_custom_domain ? 1 : 0
  hostname            = local.custom_fqdn
  app_service_name    = azurerm_linux_web_app.main.name
  resource_group_name = var.resource_group_name

  depends_on = [
    azurerm_dns_a_record.main,
    azurerm_dns_cname_record.main,
    azurerm_dns_txt_record.verification
  ]
}

# ---------------------------------------------------------------------------
# MANAGED SSL CERTIFICATE
# ---------------------------------------------------------------------------
resource "azurerm_app_service_managed_certificate" "main" {
  count                      = var.enable_custom_domain && var.enable_managed_certificate ? 1 : 0
  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.main[0].id

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# CERTIFICATE BINDING
# ---------------------------------------------------------------------------
resource "azurerm_app_service_certificate_binding" "main" {
  count               = var.enable_custom_domain && var.enable_managed_certificate ? 1 : 0
  hostname_binding_id = azurerm_app_service_custom_hostname_binding.main[0].id
  certificate_id      = azurerm_app_service_managed_certificate.main[0].id
  ssl_state           = "SniEnabled"
}
