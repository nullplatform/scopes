# =============================================================================
# AUTOSCALING
# =============================================================================

resource "azurerm_monitor_autoscale_setting" "main" {
  count               = var.enable_autoscaling ? 1 : 0
  name                = "${var.app_name}-autoscale"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.main.id

  tags = local.common_tags

  # ---------------------------------------------------------------------------
  # DEFAULT PROFILE
  # ---------------------------------------------------------------------------
  profile {
    name = "default"

    capacity {
      default = var.autoscale_default_instances
      minimum = var.autoscale_min_instances
      maximum = var.autoscale_max_instances
    }

    # -------------------------------------------------------------------------
    # CPU SCALE OUT
    # -------------------------------------------------------------------------
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.cpu_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.scale_out_cooldown
      }
    }

    # -------------------------------------------------------------------------
    # CPU SCALE IN
    # -------------------------------------------------------------------------
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.scale_in_cooldown
      }
    }

    # -------------------------------------------------------------------------
    # MEMORY SCALE OUT
    # -------------------------------------------------------------------------
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.memory_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.scale_out_cooldown
      }
    }

    # -------------------------------------------------------------------------
    # MEMORY SCALE IN
    # -------------------------------------------------------------------------
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.memory_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.scale_in_cooldown
      }
    }
  }

  # ---------------------------------------------------------------------------
  # NOTIFICATIONS
  # ---------------------------------------------------------------------------
  dynamic "notification" {
    for_each = length(var.autoscale_notification_emails) > 0 ? [1] : []
    content {
      email {
        send_to_subscription_administrator    = false
        send_to_subscription_co_administrator = false
        custom_emails                         = var.autoscale_notification_emails
      }
    }
  }
}
