# =============================================================================
# APP SERVICE PLAN
# =============================================================================

resource "azurerm_service_plan" "main" {
  name                     = local.service_plan_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  os_type                  = var.os_type
  sku_name                 = var.sku_name
  per_site_scaling_enabled = var.per_site_scaling_enabled
  zone_balancing_enabled   = var.zone_balancing_enabled

  tags = local.common_tags
}
