# =============================================================================
# APP SERVICE (Linux Web App)
# =============================================================================

resource "azurerm_linux_web_app" "main" {
  name                      = var.app_name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  service_plan_id           = azurerm_service_plan.main.id
  https_only                = var.https_only
  client_affinity_enabled   = var.client_affinity_enabled
  virtual_network_subnet_id = var.enable_vnet_integration ? var.vnet_integration_subnet_id : null

  tags = local.common_tags

  # ---------------------------------------------------------------------------
  # SITE CONFIGURATION
  # ---------------------------------------------------------------------------
  site_config {
    always_on              = var.always_on
    http2_enabled          = var.http2_enabled
    websockets_enabled     = var.websockets_enabled
    ftps_state             = var.ftps_state
    minimum_tls_version    = var.minimum_tls_version
    vnet_route_all_enabled = var.vnet_route_all_enabled
    app_command_line       = var.app_command_line != "" ? var.app_command_line : null

    # Health check
    health_check_path                 = var.health_check_path != "" ? var.health_check_path : null
    health_check_eviction_time_in_min = var.health_check_path != "" ? var.health_check_eviction_time_in_min : null

    # Docker configuration
    application_stack {
      docker_registry_url      = var.docker_registry_url
      docker_image_name        = var.docker_image
      docker_registry_username = local.docker_registry_username
      docker_registry_password = local.docker_registry_password
    }

    # IP restrictions
    ip_restriction_default_action = var.ip_restriction_default_action

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name        = ip_restriction.value.name
        ip_address  = ip_restriction.value.ip_address
        service_tag = ip_restriction.value.service_tag
        priority    = ip_restriction.value.priority
        action      = ip_restriction.value.action
      }
    }

    # Auto-heal configuration
    auto_heal_enabled = var.enable_auto_heal

    dynamic "auto_heal_setting" {
      for_each = var.enable_auto_heal ? [1] : []
      content {
        trigger {
          slow_request {
            count      = var.auto_heal_slow_request_count
            interval   = var.auto_heal_slow_request_interval
            time_taken = var.auto_heal_slow_request_time_taken
          }

          status_code {
            count             = var.auto_heal_status_code_count
            interval          = var.auto_heal_status_code_interval
            status_code_range = var.auto_heal_status_code_range
          }
        }

        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = var.auto_heal_min_process_time
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # APP SETTINGS (Environment Variables)
  # ---------------------------------------------------------------------------
  app_settings = local.app_settings

  # ---------------------------------------------------------------------------
  # LOGGING
  # ---------------------------------------------------------------------------
  dynamic "logs" {
    for_each = var.enable_logging ? [1] : []
    content {
      detailed_error_messages = var.detailed_error_messages
      failed_request_tracing  = var.failed_request_tracing

      http_logs {
        file_system {
          retention_in_days = var.http_logs_retention_days
          retention_in_mb   = var.http_logs_retention_mb
        }
      }

      application_logs {
        file_system_level = var.application_logs_level
      }
    }
  }

  # ---------------------------------------------------------------------------
  # IDENTITY
  # ---------------------------------------------------------------------------
  dynamic "identity" {
    for_each = local.identity_type != null ? [1] : []
    content {
      type         = local.identity_type
      identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
    }
  }

  # ---------------------------------------------------------------------------
  # STICKY SETTINGS (preserved during slot swap)
  # ---------------------------------------------------------------------------
  sticky_settings {
    app_setting_names = ["SLOT_NAME"]
  }
}
