# =============================================================================
# MONITORING - Application Insights & Log Analytics
# =============================================================================

# ---------------------------------------------------------------------------
# LOG ANALYTICS WORKSPACE
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_application_insights || var.enable_diagnostic_settings ? 1 : 0
  name                = local.log_analytics_workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# APPLICATION INSIGHTS
# ---------------------------------------------------------------------------
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.application_insights_name
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main[0].id

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
# ---------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "app_service" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "${var.app_name}-diagnostics"
  target_resource_id         = azurerm_linux_web_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  # HTTP logs
  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  # Console logs (stdout/stderr)
  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  # Application logs
  enabled_log {
    category = "AppServiceAppLogs"
  }

  # Platform logs
  enabled_log {
    category = "AppServicePlatformLogs"
  }

  # Audit logs
  enabled_log {
    category = "AppServiceAuditLogs"
  }

  # Metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for staging slot
resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count                      = var.enable_diagnostic_settings && var.enable_staging_slot ? 1 : 0
  name                       = "${var.app_name}-${var.staging_slot_name}-diagnostics"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
