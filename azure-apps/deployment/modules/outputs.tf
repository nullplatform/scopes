# =============================================================================
# OUTPUTS
# =============================================================================

# ---------------------------------------------------------------------------
# APP SERVICE
# ---------------------------------------------------------------------------
output "app_service_id" {
  description = "The ID of the App Service"
  value       = azurerm_linux_web_app.main.id
}

output "app_service_name" {
  description = "The name of the App Service"
  value       = azurerm_linux_web_app.main.name
}

output "app_service_default_hostname" {
  description = "The default hostname of the App Service"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "app_service_default_url" {
  description = "The default URL of the App Service"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "app_service_outbound_ip_addresses" {
  description = "Outbound IP addresses of the App Service (comma-separated)"
  value       = azurerm_linux_web_app.main.outbound_ip_addresses
}

output "app_service_outbound_ip_address_list" {
  description = "Outbound IP addresses of the App Service (list)"
  value       = azurerm_linux_web_app.main.outbound_ip_address_list
}

output "app_service_possible_outbound_ip_addresses" {
  description = "All possible outbound IP addresses of the App Service"
  value       = azurerm_linux_web_app.main.possible_outbound_ip_addresses
}

output "custom_domain_verification_id" {
  description = "Custom domain verification ID"
  value       = azurerm_linux_web_app.main.custom_domain_verification_id
  sensitive   = true
}

# ---------------------------------------------------------------------------
# APP SERVICE PLAN
# ---------------------------------------------------------------------------
output "service_plan_id" {
  description = "The ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "service_plan_name" {
  description = "The name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

# ---------------------------------------------------------------------------
# IDENTITY
# ---------------------------------------------------------------------------
output "app_service_identity_principal_id" {
  description = "The Principal ID of the App Service system-assigned identity"
  value       = var.enable_system_identity ? azurerm_linux_web_app.main.identity[0].principal_id : null
}

output "app_service_identity_tenant_id" {
  description = "The Tenant ID of the App Service system-assigned identity"
  value       = var.enable_system_identity ? azurerm_linux_web_app.main.identity[0].tenant_id : null
}

# ---------------------------------------------------------------------------
# STAGING SLOT
# ---------------------------------------------------------------------------
output "staging_slot_id" {
  description = "The ID of the staging slot"
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_hostname" {
  description = "The hostname of the staging slot"
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_slot_url" {
  description = "The URL of the staging slot"
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_traffic_percent" {
  description = "Percentage of traffic routed to staging slot"
  value       = var.enable_staging_slot ? var.staging_traffic_percent : 0
}

output "slot_swap_performed" {
  description = "Whether a slot swap was performed (staging promoted to production)"
  value       = var.enable_staging_slot && var.promote_staging_to_production
}

# ---------------------------------------------------------------------------
# CUSTOM DOMAIN
# ---------------------------------------------------------------------------
output "custom_domain_fqdn" {
  description = "The custom domain FQDN"
  value       = var.enable_custom_domain ? local.custom_fqdn : null
}

output "custom_domain_url" {
  description = "The custom domain URL"
  value       = var.enable_custom_domain ? "https://${local.custom_fqdn}" : null
}

# ---------------------------------------------------------------------------
# MONITORING
# ---------------------------------------------------------------------------
output "application_insights_id" {
  description = "The ID of the Application Insights resource"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key of Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string of Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace"
  value       = var.enable_application_insights || var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics Workspace"
  value       = var.enable_application_insights || var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.main[0].name : null
}

# ---------------------------------------------------------------------------
# KUDU / SCM (for debugging)
# ---------------------------------------------------------------------------
output "scm_url" {
  description = "The SCM (Kudu) URL for the App Service"
  value       = "https://${azurerm_linux_web_app.main.name}.scm.azurewebsites.net"
}

output "staging_scm_url" {
  description = "The SCM (Kudu) URL for the staging slot"
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app.main.name}-${var.staging_slot_name}.scm.azurewebsites.net" : null
}
