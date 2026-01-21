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
