# =============================================================================
# ALERTING
# =============================================================================

# ---------------------------------------------------------------------------
# ACTION GROUP
# ---------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_alerts && length(var.alert_email_recipients) > 0 ? 1 : 0
  name                = "${var.app_name}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = substr(var.app_name, 0, 12)

  tags = local.common_tags

  dynamic "email_receiver" {
    for_each = var.alert_email_recipients
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
}

# ---------------------------------------------------------------------------
# HTTP 5XX ERRORS ALERT
# ---------------------------------------------------------------------------
resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.enable_alerts ? 1 : 0
  name                = "${var.app_name}-http-5xx"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Alert when HTTP 5xx errors exceed threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  tags = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_http_5xx_threshold
  }

  dynamic "action" {
    for_each = length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
}

# ---------------------------------------------------------------------------
# RESPONSE TIME ALERT
# ---------------------------------------------------------------------------
resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.enable_alerts ? 1 : 0
  name                = "${var.app_name}-response-time"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Alert when response time exceeds threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  tags = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_response_time_threshold_ms / 1000 # Convert to seconds
  }

  dynamic "action" {
    for_each = length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
}

# ---------------------------------------------------------------------------
# CPU PERCENTAGE ALERT
# ---------------------------------------------------------------------------
resource "azurerm_monitor_metric_alert" "cpu_percentage" {
  count               = var.enable_alerts ? 1 : 0
  name                = "${var.app_name}-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_service_plan.main.id]
  description         = "Alert when CPU percentage exceeds threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  tags = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_cpu_percentage_threshold
  }

  dynamic "action" {
    for_each = length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
}

# ---------------------------------------------------------------------------
# MEMORY PERCENTAGE ALERT
# ---------------------------------------------------------------------------
resource "azurerm_monitor_metric_alert" "memory_percentage" {
  count               = var.enable_alerts ? 1 : 0
  name                = "${var.app_name}-memory-high"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_service_plan.main.id]
  description         = "Alert when memory percentage exceeds threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  tags = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_memory_percentage_threshold
  }

  dynamic "action" {
    for_each = length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
}

# ---------------------------------------------------------------------------
# HEALTH CHECK ALERT
# ---------------------------------------------------------------------------
resource "azurerm_monitor_metric_alert" "health_check" {
  count               = var.enable_alerts && var.health_check_path != "" ? 1 : 0
  name                = "${var.app_name}-health-check-failed"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Alert when health check status is unhealthy"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  tags = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100 # 100 = healthy, lower = unhealthy instances
  }

  dynamic "action" {
    for_each = length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
}
