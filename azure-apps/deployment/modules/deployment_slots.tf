# =============================================================================
# DEPLOYMENT SLOTS
# =============================================================================

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = var.staging_slot_name
  app_service_id = azurerm_linux_web_app.main.id

  tags = local.common_tags

  site_config {
    always_on              = var.staging_slot_always_on
    http2_enabled          = var.http2_enabled
    websockets_enabled     = var.websockets_enabled
    ftps_state             = var.ftps_state
    minimum_tls_version    = var.minimum_tls_version
    vnet_route_all_enabled = var.vnet_route_all_enabled
    app_command_line       = var.app_command_line != "" ? var.app_command_line : null

    health_check_path                 = var.health_check_path != "" ? var.health_check_path : null
    health_check_eviction_time_in_min = var.health_check_path != "" ? var.health_check_eviction_time_in_min : null

    application_stack {
      docker_registry_url      = var.docker_registry_url
      docker_image_name        = var.docker_image
      docker_registry_username = local.docker_registry_username
      docker_registry_password = local.docker_registry_password
    }
  }

  app_settings = local.staging_app_settings
  https_only   = var.https_only

  dynamic "identity" {
    for_each = local.identity_type != null ? [1] : []
    content {
      type         = local.identity_type
      identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
    }
  }
}

# =============================================================================
# TRAFFIC ROUTING
# Routes a percentage of production traffic to the staging slot
# =============================================================================

resource "null_resource" "traffic_routing" {
  count = var.enable_staging_slot && var.staging_traffic_percent > 0 ? 1 : 0

  triggers = {
    traffic_percent = var.staging_traffic_percent
    app_name        = azurerm_linux_web_app.main.name
    slot_name       = var.staging_slot_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      az webapp traffic-routing set \
        --resource-group ${var.resource_group_name} \
        --name ${azurerm_linux_web_app.main.name} \
        --distribution ${var.staging_slot_name}=${var.staging_traffic_percent}
    EOT
  }

  depends_on = [azurerm_linux_web_app_slot.staging]
}

# Clear traffic routing when percentage is set to 0
resource "null_resource" "clear_traffic_routing" {
  count = var.enable_staging_slot && var.staging_traffic_percent == 0 ? 1 : 0

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      az webapp traffic-routing clear \
        --resource-group ${var.resource_group_name} \
        --name ${azurerm_linux_web_app.main.name}
    EOT
  }

  depends_on = [azurerm_linux_web_app_slot.staging]
}

# =============================================================================
# SLOT SWAP (Promote staging to production)
# When promote_staging_to_production is true, swaps staging with production
# =============================================================================

resource "azurerm_web_app_active_slot" "slot_swap" {
  count = var.enable_staging_slot && var.promote_staging_to_production ? 1 : 0

  slot_id = azurerm_linux_web_app_slot.staging[0].id

  # Ensure traffic routing is cleared before swap
  depends_on = [null_resource.clear_traffic_routing]
}
