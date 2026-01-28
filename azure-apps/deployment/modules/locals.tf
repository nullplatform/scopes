# =============================================================================
# LOCALS - Computed values and defaults
# =============================================================================

locals {
  # Resource naming with fallbacks
  service_plan_name            = var.service_plan_name != "" ? var.service_plan_name : "${var.app_name}-plan"
  application_insights_name    = var.application_insights_name != "" ? var.application_insights_name : "${var.app_name}-insights"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "${var.app_name}-logs"

  # Parse environment variables from JSON
  env_variables = jsondecode(var.parameter_json)

  # Construct custom domain FQDN
  custom_fqdn = var.enable_custom_domain ? (
    var.custom_subdomain == "@" ? var.dns_zone_name : "${var.custom_subdomain}.${var.dns_zone_name}"
  ) : ""

  # Common tags applied to all resources
  common_tags = merge(var.resource_tags, {
    managed_by = "terraform"
  })

  # Docker registry credentials (only if provided)
  docker_registry_username = var.docker_registry_username != "" ? var.docker_registry_username : null
  docker_registry_password = var.docker_registry_password != "" ? var.docker_registry_password : null

  # Staging slot docker image (defaults to production image if not specified)
  staging_docker_image = var.staging_docker_image != "" ? var.staging_docker_image : var.docker_image

  # App settings combining user env vars with required settings
  base_app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    DOCKER_ENABLE_CI                    = "true"
  }

  app_insights_settings = var.enable_application_insights ? {
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main[0].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.main[0].instrumentation_key
  } : {}

  app_settings = merge(
    local.env_variables,
    local.base_app_settings,
    local.app_insights_settings
  )

  # Staging slot app settings
  staging_app_settings = merge(
    local.app_settings,
    {
      SLOT_NAME = var.staging_slot_name
    }
  )

  # Identity type based on configuration
  identity_type = (
    var.enable_system_identity && length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" :
    var.enable_system_identity ? "SystemAssigned" :
    length(var.user_assigned_identity_ids) > 0 ? "UserAssigned" :
    null
  )
}
