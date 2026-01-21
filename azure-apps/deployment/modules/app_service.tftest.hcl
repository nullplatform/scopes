# =============================================================================
# Unit tests for azure-apps/deployment/modules
#
# Run: tofu test
# =============================================================================

mock_provider "azurerm" {
  mock_resource "azurerm_linux_web_app" {
    defaults = {
      id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Web/sites/my-test-app"
      default_hostname = "my-test-app.azurewebsites.net"
      outbound_ip_addresses          = "1.2.3.4,5.6.7.8"
      outbound_ip_address_list       = ["1.2.3.4", "5.6.7.8"]
      possible_outbound_ip_addresses = "1.2.3.4,5.6.7.8,9.10.11.12"
      custom_domain_verification_id  = "abc123"
    }
  }

  mock_resource "azurerm_service_plan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Web/serverFarms/my-test-app-plan"
    }
  }

  mock_resource "azurerm_linux_web_app_slot" {
    defaults = {
      id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Web/sites/my-test-app/slots/staging"
      default_hostname = "my-test-app-staging.azurewebsites.net"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/my-test-app-logs"
    }
  }

  mock_resource "azurerm_application_insights" {
    defaults = {
      id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/microsoft.insights/components/my-test-app-insights"
      connection_string  = "InstrumentationKey=00000000-0000-0000-0000-000000000000"
      instrumentation_key = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "azurerm_monitor_autoscale_setting" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/microsoft.insights/autoscalesettings/my-test-app-autoscale"
    }
  }

  mock_resource "azurerm_monitor_diagnostic_setting" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Insights/diagnosticSettings/my-test-app-diagnostics"
    }
  }

  mock_data "azurerm_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/dnszones/example.com"
    }
  }

  mock_resource "azurerm_dns_a_record" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/dnszones/example.com/A/@"
    }
  }

  mock_resource "azurerm_dns_cname_record" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/dnszones/example.com/CNAME/api"
    }
  }

  mock_resource "azurerm_dns_txt_record" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/dnszones/example.com/TXT/asuid"
    }
  }

  mock_resource "azurerm_app_service_custom_hostname_binding" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Web/sites/my-test-app/hostNameBindings/api.example.com"
    }
  }

  mock_resource "azurerm_app_service_managed_certificate" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Web/certificates/my-test-app-cert"
    }
  }

  mock_resource "azurerm_app_service_certificate_binding" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Web/sites/my-test-app/hostNameBindings/api.example.com/certificate"
    }
  }

  mock_resource "azurerm_monitor_action_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/microsoft.insights/actionGroups/my-test-app-alerts"
    }
  }

  mock_resource "azurerm_monitor_metric_alert" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/microsoft.insights/metricAlerts/my-test-app-alert"
    }
  }
}

# =============================================================================
# DEFAULT VARIABLES
# =============================================================================
variables {
  resource_group_name = "test-rg"
  location            = "eastus"
  app_name            = "my-test-app"
  docker_image        = "nginx:latest"
  sku_name            = "P1v3"
  resource_tags       = {
    Environment = "test"
    Team        = "platform"
  }
}

# =============================================================================
# CORE CONFIGURATION TESTS
# =============================================================================

run "core_app_name_set_correctly" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.name == "my-test-app"
    error_message = "App service name should be 'my-test-app'"
  }
}

run "core_location_set_correctly" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.location == "eastus"
    error_message = "Location should be 'eastus'"
  }
  assert {
    condition     = azurerm_service_plan.main.location == "eastus"
    error_message = "Service plan location should be 'eastus'"
  }
}

run "core_resource_group_set_correctly" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.resource_group_name == "test-rg"
    error_message = "Resource group should be 'test-rg'"
  }
}

run "core_tags_propagated_to_all_resources" {
  command = plan
  assert {
    condition     = azurerm_service_plan.main.tags["Environment"] == "test"
    error_message = "Service plan should have Environment tag"
  }
  assert {
    condition     = azurerm_service_plan.main.tags["Team"] == "platform"
    error_message = "Service plan should have Team tag"
  }
  assert {
    condition     = azurerm_service_plan.main.tags["managed_by"] == "terraform"
    error_message = "Service plan should have managed_by tag"
  }
}

run "core_parameter_json_parsed_to_env_vars" {
  command = plan
  variables {
    parameter_json = "{\"DATABASE_URL\": \"postgres://localhost\", \"API_KEY\": \"secret123\"}"
  }
  assert {
    condition     = local.env_variables["DATABASE_URL"] == "postgres://localhost"
    error_message = "DATABASE_URL should be parsed from parameter_json"
  }
  assert {
    condition     = local.env_variables["API_KEY"] == "secret123"
    error_message = "API_KEY should be parsed from parameter_json"
  }
}

run "core_app_settings_include_base_settings" {
  command = plan
  assert {
    condition     = local.base_app_settings["WEBSITES_ENABLE_APP_SERVICE_STORAGE"] == "false"
    error_message = "App settings should include WEBSITES_ENABLE_APP_SERVICE_STORAGE"
  }
  assert {
    condition     = local.base_app_settings["DOCKER_ENABLE_CI"] == "true"
    error_message = "App settings should include DOCKER_ENABLE_CI"
  }
}

# =============================================================================
# APP SERVICE PLAN TESTS
# =============================================================================

run "plan_default_name_generated" {
  command = plan
  assert {
    condition     = azurerm_service_plan.main.name == "my-test-app-plan"
    error_message = "Service plan name should default to 'my-test-app-plan'"
  }
}

run "plan_custom_name_override" {
  command = plan
  variables {
    service_plan_name = "custom-plan-name"
  }
  assert {
    condition     = azurerm_service_plan.main.name == "custom-plan-name"
    error_message = "Service plan name should be 'custom-plan-name'"
  }
}

run "plan_sku_name_set" {
  command = plan
  assert {
    condition     = azurerm_service_plan.main.sku_name == "P1v3"
    error_message = "Service plan SKU should be 'P1v3'"
  }
}

run "plan_os_type_default_linux" {
  command = plan
  assert {
    condition     = azurerm_service_plan.main.os_type == "Linux"
    error_message = "OS type should default to 'Linux'"
  }
}

run "plan_per_site_scaling_disabled_by_default" {
  command = plan
  assert {
    condition     = azurerm_service_plan.main.per_site_scaling_enabled == false
    error_message = "Per-site scaling should be disabled by default"
  }
}

run "plan_per_site_scaling_enabled_when_set" {
  command = plan
  variables {
    per_site_scaling_enabled = true
  }
  assert {
    condition     = azurerm_service_plan.main.per_site_scaling_enabled == true
    error_message = "Per-site scaling should be enabled when set"
  }
}

run "plan_zone_balancing_disabled_by_default" {
  command = plan
  assert {
    condition     = azurerm_service_plan.main.zone_balancing_enabled == false
    error_message = "Zone balancing should be disabled by default"
  }
}

run "plan_zone_balancing_enabled_when_set" {
  command = plan
  variables {
    zone_balancing_enabled = true
  }
  assert {
    condition     = azurerm_service_plan.main.zone_balancing_enabled == true
    error_message = "Zone balancing should be enabled when set"
  }
}

# =============================================================================
# DOCKER / CONTAINER TESTS
# =============================================================================

run "docker_image_set_correctly" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].application_stack[0].docker_image_name == "nginx:latest"
    error_message = "Docker image should be 'nginx:latest'"
  }
}

run "docker_registry_url_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].application_stack[0].docker_registry_url == "https://index.docker.io"
    error_message = "Docker registry URL should default to Docker Hub"
  }
}

run "docker_registry_url_custom" {
  command = plan
  variables {
    docker_registry_url = "https://myregistry.azurecr.io"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].application_stack[0].docker_registry_url == "https://myregistry.azurecr.io"
    error_message = "Docker registry URL should be set to custom value"
  }
}

run "docker_credentials_null_when_empty" {
  command = plan
  assert {
    condition     = local.docker_registry_username == null
    error_message = "Docker registry username should be null when not provided"
  }
  assert {
    condition     = local.docker_registry_password == null
    error_message = "Docker registry password should be null when not provided"
  }
}

run "docker_credentials_set_when_provided" {
  command = plan
  variables {
    docker_registry_username = "myuser"
    docker_registry_password = "mypassword"
  }
  assert {
    condition     = local.docker_registry_username == "myuser"
    error_message = "Docker registry username should be set"
  }
  assert {
    condition     = local.docker_registry_password == "mypassword"
    error_message = "Docker registry password should be set"
  }
}

# =============================================================================
# APP SERVICE CONFIGURATION TESTS
# =============================================================================

run "config_always_on_default_true" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].always_on == true
    error_message = "Always on should be enabled by default"
  }
}

run "config_always_on_can_be_disabled" {
  command = plan
  variables {
    always_on = false
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].always_on == false
    error_message = "Always on should be disabled when set to false"
  }
}

run "config_https_only_default_true" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.https_only == true
    error_message = "HTTPS only should be enabled by default"
  }
}

run "config_https_only_can_be_disabled" {
  command = plan
  variables {
    https_only = false
  }
  assert {
    condition     = azurerm_linux_web_app.main.https_only == false
    error_message = "HTTPS only should be disabled when set to false"
  }
}

run "config_http2_enabled_default_true" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].http2_enabled == true
    error_message = "HTTP/2 should be enabled by default"
  }
}

run "config_websockets_disabled_by_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].websockets_enabled == false
    error_message = "WebSockets should be disabled by default"
  }
}

run "config_websockets_enabled_when_set" {
  command = plan
  variables {
    websockets_enabled = true
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].websockets_enabled == true
    error_message = "WebSockets should be enabled when set"
  }
}

run "config_ftps_state_default_disabled" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].ftps_state == "Disabled"
    error_message = "FTPS should be disabled by default"
  }
}

run "config_ftps_state_can_be_changed" {
  command = plan
  variables {
    ftps_state = "FtpsOnly"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].ftps_state == "FtpsOnly"
    error_message = "FTPS state should be 'FtpsOnly'"
  }
}

run "config_minimum_tls_version_default_1_2" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].minimum_tls_version == "1.2"
    error_message = "Minimum TLS version should default to 1.2"
  }
}

run "config_client_affinity_disabled_by_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.client_affinity_enabled == false
    error_message = "Client affinity should be disabled by default"
  }
}

run "config_client_affinity_enabled_when_set" {
  command = plan
  variables {
    client_affinity_enabled = true
  }
  assert {
    condition     = azurerm_linux_web_app.main.client_affinity_enabled == true
    error_message = "Client affinity should be enabled when set"
  }
}

run "config_app_command_line_null_when_empty" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].app_command_line == null
    error_message = "App command line should be null when not provided"
  }
}

run "config_app_command_line_set_when_provided" {
  command = plan
  variables {
    app_command_line = "npm start"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].app_command_line == "npm start"
    error_message = "App command line should be 'npm start'"
  }
}

# =============================================================================
# HEALTH CHECK TESTS
# =============================================================================

run "health_check_disabled_by_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].health_check_path == null
    error_message = "Health check path should be null when not configured"
  }
}

run "health_check_enabled_when_path_provided" {
  command = plan
  variables {
    health_check_path = "/health"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].health_check_path == "/health"
    error_message = "Health check path should be '/health'"
  }
}

run "health_check_eviction_time_set_when_path_provided" {
  command = plan
  variables {
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 5
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].health_check_eviction_time_in_min == 5
    error_message = "Health check eviction time should be 5 minutes"
  }
}

# =============================================================================
# DEPLOYMENT SLOTS TESTS
# =============================================================================

run "slot_disabled_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_linux_web_app_slot.staging) == 0
    error_message = "Staging slot should not be created by default"
  }
}

run "slot_created_when_enabled" {
  command = plan
  variables {
    enable_staging_slot = true
  }
  assert {
    condition     = length(azurerm_linux_web_app_slot.staging) == 1
    error_message = "Staging slot should be created when enabled"
  }
}

run "slot_default_name_staging" {
  command = plan
  variables {
    enable_staging_slot = true
  }
  assert {
    condition     = azurerm_linux_web_app_slot.staging[0].name == "staging"
    error_message = "Slot name should default to 'staging'"
  }
}

run "slot_custom_name" {
  command = plan
  variables {
    enable_staging_slot = true
    staging_slot_name   = "preview"
  }
  assert {
    condition     = azurerm_linux_web_app_slot.staging[0].name == "preview"
    error_message = "Slot name should be 'preview'"
  }
}

run "slot_always_on_default_false" {
  command = plan
  variables {
    enable_staging_slot = true
  }
  assert {
    condition     = azurerm_linux_web_app_slot.staging[0].site_config[0].always_on == false
    error_message = "Staging slot always_on should default to false"
  }
}

run "slot_always_on_enabled_when_set" {
  command = plan
  variables {
    enable_staging_slot    = true
    staging_slot_always_on = true
  }
  assert {
    condition     = azurerm_linux_web_app_slot.staging[0].site_config[0].always_on == true
    error_message = "Staging slot always_on should be enabled when set"
  }
}

run "slot_inherits_https_only" {
  command = plan
  variables {
    enable_staging_slot = true
  }
  assert {
    condition     = azurerm_linux_web_app_slot.staging[0].https_only == true
    error_message = "Staging slot should inherit https_only setting"
  }
}

run "slot_has_slot_name_env_var" {
  command = plan
  variables {
    enable_staging_slot = true
    staging_slot_name   = "staging"
  }
  assert {
    condition     = local.staging_app_settings["SLOT_NAME"] == "staging"
    error_message = "Staging slot should have SLOT_NAME env var"
  }
}

# =============================================================================
# CUSTOM DOMAIN TESTS
# =============================================================================

run "domain_disabled_by_default" {
  command = plan
  assert {
    condition     = local.custom_fqdn == ""
    error_message = "Custom FQDN should be empty when not enabled"
  }
}

run "domain_fqdn_with_subdomain" {
  command = plan
  variables {
    enable_custom_domain    = true
    dns_zone_name           = "example.com"
    dns_zone_resource_group = "dns-rg"
    custom_subdomain        = "api"
  }
  assert {
    condition     = local.custom_fqdn == "api.example.com"
    error_message = "Custom FQDN should be 'api.example.com'"
  }
}

run "domain_fqdn_apex_domain" {
  command = plan
  variables {
    enable_custom_domain    = true
    dns_zone_name           = "example.com"
    dns_zone_resource_group = "dns-rg"
    custom_subdomain        = "@"
  }
  assert {
    condition     = local.custom_fqdn == "example.com"
    error_message = "Custom FQDN for apex should be 'example.com'"
  }
}

run "domain_cname_record_created_for_subdomain" {
  command = plan
  variables {
    enable_custom_domain    = true
    dns_zone_name           = "example.com"
    dns_zone_resource_group = "dns-rg"
    custom_subdomain        = "api"
  }
  assert {
    condition     = length(azurerm_dns_cname_record.main) == 1
    error_message = "CNAME record should be created for subdomain"
  }
  assert {
    condition     = length(azurerm_dns_a_record.main) == 0
    error_message = "A record should not be created for subdomain"
  }
}

run "domain_a_record_created_for_apex" {
  command = plan
  variables {
    enable_custom_domain    = true
    dns_zone_name           = "example.com"
    dns_zone_resource_group = "dns-rg"
    custom_subdomain        = "@"
  }
  assert {
    condition     = length(azurerm_dns_a_record.main) == 1
    error_message = "A record should be created for apex domain"
  }
  assert {
    condition     = length(azurerm_dns_cname_record.main) == 0
    error_message = "CNAME record should not be created for apex domain"
  }
}

run "domain_managed_certificate_created_by_default" {
  command = plan
  variables {
    enable_custom_domain    = true
    dns_zone_name           = "example.com"
    dns_zone_resource_group = "dns-rg"
    custom_subdomain        = "api"
  }
  assert {
    condition     = length(azurerm_app_service_managed_certificate.main) == 1
    error_message = "Managed certificate should be created by default"
  }
}

run "domain_managed_certificate_disabled_when_set" {
  command = plan
  variables {
    enable_custom_domain       = true
    dns_zone_name              = "example.com"
    dns_zone_resource_group    = "dns-rg"
    custom_subdomain           = "api"
    enable_managed_certificate = false
  }
  assert {
    condition     = length(azurerm_app_service_managed_certificate.main) == 0
    error_message = "Managed certificate should not be created when disabled"
  }
}

# =============================================================================
# LOGGING TESTS
# =============================================================================

run "logging_enabled_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_linux_web_app.main.logs) == 1
    error_message = "Logging should be enabled by default"
  }
}

run "logging_disabled_when_set" {
  command = plan
  variables {
    enable_logging = false
  }
  assert {
    condition     = length(azurerm_linux_web_app.main.logs) == 0
    error_message = "Logging should be disabled when set to false"
  }
}

run "logging_detailed_error_messages_default_true" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.logs[0].detailed_error_messages == true
    error_message = "Detailed error messages should be enabled by default"
  }
}

run "logging_failed_request_tracing_default_true" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.logs[0].failed_request_tracing == true
    error_message = "Failed request tracing should be enabled by default"
  }
}

run "logging_http_retention_days_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.logs[0].http_logs[0].file_system[0].retention_in_days == 7
    error_message = "HTTP logs retention should default to 7 days"
  }
}

run "logging_http_retention_days_custom" {
  command = plan
  variables {
    http_logs_retention_days = 30
  }
  assert {
    condition     = azurerm_linux_web_app.main.logs[0].http_logs[0].file_system[0].retention_in_days == 30
    error_message = "HTTP logs retention should be 30 days"
  }
}

run "logging_http_retention_mb_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.logs[0].http_logs[0].file_system[0].retention_in_mb == 35
    error_message = "HTTP logs retention should default to 35 MB"
  }
}

run "logging_application_level_default_information" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.logs[0].application_logs[0].file_system_level == "Information"
    error_message = "Application log level should default to 'Information'"
  }
}

run "logging_application_level_custom" {
  command = plan
  variables {
    application_logs_level = "Verbose"
  }
  assert {
    condition     = azurerm_linux_web_app.main.logs[0].application_logs[0].file_system_level == "Verbose"
    error_message = "Application log level should be 'Verbose'"
  }
}

# =============================================================================
# APPLICATION INSIGHTS TESTS
# =============================================================================

run "insights_disabled_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_application_insights.main) == 0
    error_message = "Application Insights should not be created by default"
  }
}

run "insights_created_when_enabled" {
  command = plan
  variables {
    enable_application_insights = true
  }
  assert {
    condition     = length(azurerm_application_insights.main) == 1
    error_message = "Application Insights should be created when enabled"
  }
}

run "insights_log_analytics_created_when_insights_enabled" {
  command = plan
  variables {
    enable_application_insights = true
  }
  assert {
    condition     = length(azurerm_log_analytics_workspace.main) == 1
    error_message = "Log Analytics Workspace should be created with Application Insights"
  }
}

run "insights_default_name_generated" {
  command = plan
  variables {
    enable_application_insights = true
  }
  assert {
    condition     = azurerm_application_insights.main[0].name == "my-test-app-insights"
    error_message = "Application Insights name should default to 'my-test-app-insights'"
  }
}

run "insights_custom_name_override" {
  command = plan
  variables {
    enable_application_insights = true
    application_insights_name   = "custom-insights"
  }
  assert {
    condition     = azurerm_application_insights.main[0].name == "custom-insights"
    error_message = "Application Insights name should be 'custom-insights'"
  }
}

run "insights_log_analytics_default_name" {
  command = plan
  variables {
    enable_application_insights = true
  }
  assert {
    condition     = azurerm_log_analytics_workspace.main[0].name == "my-test-app-logs"
    error_message = "Log Analytics Workspace name should default to 'my-test-app-logs'"
  }
}

run "insights_log_analytics_custom_name" {
  command = plan
  variables {
    enable_application_insights    = true
    log_analytics_workspace_name   = "custom-logs"
  }
  assert {
    condition     = azurerm_log_analytics_workspace.main[0].name == "custom-logs"
    error_message = "Log Analytics Workspace name should be 'custom-logs'"
  }
}

run "insights_log_analytics_retention_default" {
  command = plan
  variables {
    enable_application_insights = true
  }
  assert {
    condition     = azurerm_log_analytics_workspace.main[0].retention_in_days == 30
    error_message = "Log Analytics retention should default to 30 days"
  }
}

run "insights_log_analytics_retention_custom" {
  command = plan
  variables {
    enable_application_insights  = true
    log_analytics_retention_days = 90
  }
  assert {
    condition     = azurerm_log_analytics_workspace.main[0].retention_in_days == 90
    error_message = "Log Analytics retention should be 90 days"
  }
}

run "insights_app_settings_include_connection_string" {
  command = plan
  variables {
    enable_application_insights = true
  }
  assert {
    condition     = can(local.app_insights_settings["APPLICATIONINSIGHTS_CONNECTION_STRING"])
    error_message = "App settings should include Application Insights connection string"
  }
}

# =============================================================================
# DIAGNOSTIC SETTINGS TESTS
# =============================================================================

run "diagnostics_disabled_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.app_service) == 0
    error_message = "Diagnostic settings should not be created by default"
  }
}

run "diagnostics_created_when_enabled" {
  command = plan
  variables {
    enable_diagnostic_settings = true
  }
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.app_service) == 1
    error_message = "Diagnostic settings should be created when enabled"
  }
}

run "diagnostics_creates_log_analytics" {
  command = plan
  variables {
    enable_diagnostic_settings = true
  }
  assert {
    condition     = length(azurerm_log_analytics_workspace.main) == 1
    error_message = "Log Analytics should be created for diagnostic settings"
  }
}

run "diagnostics_staging_slot_created_when_both_enabled" {
  command = plan
  variables {
    enable_diagnostic_settings = true
    enable_staging_slot        = true
  }
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.staging_slot) == 1
    error_message = "Staging slot diagnostic settings should be created"
  }
}

# =============================================================================
# AUTOSCALING TESTS
# =============================================================================

run "autoscaling_disabled_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_monitor_autoscale_setting.main) == 0
    error_message = "Autoscaling should not be created by default"
  }
}

run "autoscaling_created_when_enabled" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = length(azurerm_monitor_autoscale_setting.main) == 1
    error_message = "Autoscaling should be created when enabled"
  }
}

run "autoscaling_min_instances_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].capacity[0].minimum == 1
    error_message = "Autoscale min instances should default to 1"
  }
}

run "autoscaling_max_instances_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].capacity[0].maximum == 10
    error_message = "Autoscale max instances should default to 10"
  }
}

run "autoscaling_default_instances_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].capacity[0].default == 2
    error_message = "Autoscale default instances should default to 2"
  }
}

run "autoscaling_custom_capacity" {
  command = plan
  variables {
    enable_autoscaling          = true
    autoscale_min_instances     = 3
    autoscale_max_instances     = 20
    autoscale_default_instances = 5
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].capacity[0].minimum == 3
    error_message = "Autoscale min instances should be 3"
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].capacity[0].maximum == 20
    error_message = "Autoscale max instances should be 20"
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].capacity[0].default == 5
    error_message = "Autoscale default instances should be 5"
  }
}

run "autoscaling_cpu_scale_out_threshold_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[0].metric_trigger[0].threshold == 70
    error_message = "CPU scale out threshold should default to 70"
  }
}

run "autoscaling_cpu_scale_in_threshold_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[1].metric_trigger[0].threshold == 30
    error_message = "CPU scale in threshold should default to 30"
  }
}

run "autoscaling_memory_scale_out_threshold_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[2].metric_trigger[0].threshold == 75
    error_message = "Memory scale out threshold should default to 75"
  }
}

run "autoscaling_memory_scale_in_threshold_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[3].metric_trigger[0].threshold == 40
    error_message = "Memory scale in threshold should default to 40"
  }
}

run "autoscaling_custom_thresholds" {
  command = plan
  variables {
    enable_autoscaling         = true
    cpu_scale_out_threshold    = 80
    cpu_scale_in_threshold     = 20
    memory_scale_out_threshold = 85
    memory_scale_in_threshold  = 30
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[0].metric_trigger[0].threshold == 80
    error_message = "CPU scale out threshold should be 80"
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[1].metric_trigger[0].threshold == 20
    error_message = "CPU scale in threshold should be 20"
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[2].metric_trigger[0].threshold == 85
    error_message = "Memory scale out threshold should be 85"
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[3].metric_trigger[0].threshold == 30
    error_message = "Memory scale in threshold should be 30"
  }
}

run "autoscaling_scale_out_cooldown_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[0].scale_action[0].cooldown == "PT5M"
    error_message = "Scale out cooldown should default to PT5M"
  }
}

run "autoscaling_scale_in_cooldown_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[1].scale_action[0].cooldown == "PT10M"
    error_message = "Scale in cooldown should default to PT10M"
  }
}

run "autoscaling_custom_cooldowns" {
  command = plan
  variables {
    enable_autoscaling = true
    scale_out_cooldown = "PT10M"
    scale_in_cooldown  = "PT15M"
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[0].scale_action[0].cooldown == "PT10M"
    error_message = "Scale out cooldown should be PT10M"
  }
  assert {
    condition     = azurerm_monitor_autoscale_setting.main[0].profile[0].rule[1].scale_action[0].cooldown == "PT15M"
    error_message = "Scale in cooldown should be PT15M"
  }
}

run "autoscaling_no_notifications_by_default" {
  command = plan
  variables {
    enable_autoscaling = true
  }
  assert {
    condition     = length(azurerm_monitor_autoscale_setting.main[0].notification) == 0
    error_message = "Autoscaling should not have notifications by default"
  }
}

run "autoscaling_notifications_when_emails_provided" {
  command = plan
  variables {
    enable_autoscaling            = true
    autoscale_notification_emails = ["ops@example.com", "dev@example.com"]
  }
  assert {
    condition     = length(azurerm_monitor_autoscale_setting.main[0].notification) == 1
    error_message = "Autoscaling should have notifications when emails provided"
  }
}

# =============================================================================
# AUTO-HEAL TESTS
# =============================================================================

run "auto_heal_disabled_by_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_enabled == null
    error_message = "Auto-heal should be null (disabled) by default"
  }
}

run "auto_heal_enabled_when_configured" {
  command = plan
  variables {
    enable_auto_heal = true
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_enabled == true
    error_message = "Auto-heal should be enabled when configured"
  }
}

run "auto_heal_slow_request_defaults" {
  command = plan
  variables {
    enable_auto_heal = true
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].slow_request[0].count == 10
    error_message = "Auto-heal slow request count should default to 10"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].slow_request[0].interval == "00:01:00"
    error_message = "Auto-heal slow request interval should default to 00:01:00"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].slow_request[0].time_taken == "00:00:30"
    error_message = "Auto-heal slow request time taken should default to 00:00:30"
  }
}

run "auto_heal_slow_request_custom" {
  command = plan
  variables {
    enable_auto_heal                  = true
    auto_heal_slow_request_count      = 20
    auto_heal_slow_request_interval   = "00:02:00"
    auto_heal_slow_request_time_taken = "00:01:00"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].slow_request[0].count == 20
    error_message = "Auto-heal slow request count should be 20"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].slow_request[0].interval == "00:02:00"
    error_message = "Auto-heal slow request interval should be 00:02:00"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].slow_request[0].time_taken == "00:01:00"
    error_message = "Auto-heal slow request time taken should be 00:01:00"
  }
}

run "auto_heal_status_code_defaults" {
  command = plan
  variables {
    enable_auto_heal = true
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].status_code[0].count == 50
    error_message = "Auto-heal status code count should default to 50"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].status_code[0].interval == "00:05:00"
    error_message = "Auto-heal status code interval should default to 00:05:00"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].status_code[0].status_code_range == "500-599"
    error_message = "Auto-heal status code range should default to 500-599"
  }
}

run "auto_heal_status_code_custom" {
  command = plan
  variables {
    enable_auto_heal               = true
    auto_heal_status_code_count    = 100
    auto_heal_status_code_interval = "00:10:00"
    auto_heal_status_code_range    = "400-599"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].status_code[0].count == 100
    error_message = "Auto-heal status code count should be 100"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].status_code[0].interval == "00:10:00"
    error_message = "Auto-heal status code interval should be 00:10:00"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].trigger[0].status_code[0].status_code_range == "400-599"
    error_message = "Auto-heal status code range should be 400-599"
  }
}

run "auto_heal_action_recycle" {
  command = plan
  variables {
    enable_auto_heal = true
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].action[0].action_type == "Recycle"
    error_message = "Auto-heal action type should be Recycle"
  }
}

run "auto_heal_min_process_time_default" {
  command = plan
  variables {
    enable_auto_heal = true
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].action[0].minimum_process_execution_time == "00:01:00"
    error_message = "Auto-heal min process time should default to 00:01:00"
  }
}

run "auto_heal_min_process_time_custom" {
  command = plan
  variables {
    enable_auto_heal            = true
    auto_heal_min_process_time  = "00:05:00"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].auto_heal_setting[0].action[0].minimum_process_execution_time == "00:05:00"
    error_message = "Auto-heal min process time should be 00:05:00"
  }
}

# =============================================================================
# NETWORKING TESTS
# =============================================================================

run "vnet_integration_disabled_by_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.virtual_network_subnet_id == null
    error_message = "VNet integration should be disabled by default"
  }
}

run "vnet_integration_enabled_when_set" {
  command = plan
  variables {
    enable_vnet_integration    = true
    vnet_integration_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/app-subnet"
  }
  assert {
    condition     = azurerm_linux_web_app.main.virtual_network_subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/app-subnet"
    error_message = "VNet integration subnet ID should be set"
  }
}

run "vnet_route_all_disabled_by_default" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].vnet_route_all_enabled == false
    error_message = "VNet route all should be disabled by default"
  }
}

run "vnet_route_all_enabled_when_set" {
  command = plan
  variables {
    vnet_route_all_enabled = true
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].vnet_route_all_enabled == true
    error_message = "VNet route all should be enabled when set"
  }
}

run "ip_restriction_default_action_allow" {
  command = plan
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].ip_restriction_default_action == "Allow"
    error_message = "IP restriction default action should be 'Allow'"
  }
}

run "ip_restriction_default_action_deny" {
  command = plan
  variables {
    ip_restriction_default_action = "Deny"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].ip_restriction_default_action == "Deny"
    error_message = "IP restriction default action should be 'Deny'"
  }
}

run "ip_restrictions_none_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_linux_web_app.main.site_config[0].ip_restriction) == 0
    error_message = "No IP restrictions should exist by default"
  }
}

run "ip_restrictions_added_when_provided" {
  command = plan
  variables {
    ip_restrictions = [
      {
        name       = "allow-office"
        ip_address = "203.0.113.0/24"
        priority   = 100
        action     = "Allow"
      }
    ]
  }
  assert {
    condition     = length(azurerm_linux_web_app.main.site_config[0].ip_restriction) == 1
    error_message = "IP restriction should be added"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].ip_restriction[0].name == "allow-office"
    error_message = "IP restriction name should be 'allow-office'"
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].ip_restriction[0].ip_address == "203.0.113.0/24"
    error_message = "IP restriction IP address should be set"
  }
}

run "ip_restrictions_service_tag" {
  command = plan
  variables {
    ip_restrictions = [
      {
        name        = "allow-azure"
        service_tag = "AzureCloud"
        priority    = 100
        action      = "Allow"
      }
    ]
  }
  assert {
    condition     = azurerm_linux_web_app.main.site_config[0].ip_restriction[0].service_tag == "AzureCloud"
    error_message = "IP restriction service tag should be 'AzureCloud'"
  }
}

# =============================================================================
# IDENTITY TESTS
# =============================================================================

run "identity_none_by_default" {
  command = plan
  assert {
    condition     = local.identity_type == null
    error_message = "Identity type should be null by default"
  }
}

run "identity_system_assigned" {
  command = plan
  variables {
    enable_system_identity = true
  }
  assert {
    condition     = local.identity_type == "SystemAssigned"
    error_message = "Identity type should be 'SystemAssigned'"
  }
}

run "identity_user_assigned" {
  command = plan
  variables {
    user_assigned_identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/my-identity"]
  }
  assert {
    condition     = local.identity_type == "UserAssigned"
    error_message = "Identity type should be 'UserAssigned'"
  }
}

run "identity_system_and_user_assigned" {
  command = plan
  variables {
    enable_system_identity     = true
    user_assigned_identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/my-identity"]
  }
  assert {
    condition     = local.identity_type == "SystemAssigned, UserAssigned"
    error_message = "Identity type should be 'SystemAssigned, UserAssigned'"
  }
}

run "identity_block_created_when_enabled" {
  command = plan
  variables {
    enable_system_identity = true
  }
  assert {
    condition     = length(azurerm_linux_web_app.main.identity) == 1
    error_message = "Identity block should be created when enabled"
  }
}

run "identity_block_not_created_when_disabled" {
  command = plan
  assert {
    condition     = length(azurerm_linux_web_app.main.identity) == 0
    error_message = "Identity block should not be created when disabled"
  }
}

# =============================================================================
# ALERTING TESTS
# =============================================================================

run "alerts_disabled_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_monitor_metric_alert.http_5xx) == 0
    error_message = "HTTP 5xx alert should not be created by default"
  }
}

run "alerts_created_when_enabled" {
  command = plan
  variables {
    enable_alerts = true
  }
  assert {
    condition     = length(azurerm_monitor_metric_alert.http_5xx) == 1
    error_message = "HTTP 5xx alert should be created when enabled"
  }
  assert {
    condition     = length(azurerm_monitor_metric_alert.response_time) == 1
    error_message = "Response time alert should be created when enabled"
  }
  assert {
    condition     = length(azurerm_monitor_metric_alert.cpu_percentage) == 1
    error_message = "CPU percentage alert should be created when enabled"
  }
  assert {
    condition     = length(azurerm_monitor_metric_alert.memory_percentage) == 1
    error_message = "Memory percentage alert should be created when enabled"
  }
}

run "alerts_action_group_requires_emails" {
  command = plan
  variables {
    enable_alerts = true
  }
  assert {
    condition     = length(azurerm_monitor_action_group.main) == 0
    error_message = "Action group should not be created without email recipients"
  }
}

run "alerts_action_group_created_with_emails" {
  command = plan
  variables {
    enable_alerts           = true
    alert_email_recipients  = ["ops@example.com"]
  }
  assert {
    condition     = length(azurerm_monitor_action_group.main) == 1
    error_message = "Action group should be created with email recipients"
  }
}

run "alerts_http_5xx_threshold_default" {
  command = plan
  variables {
    enable_alerts = true
  }
  assert {
    condition     = azurerm_monitor_metric_alert.http_5xx[0].criteria[0].threshold == 10
    error_message = "HTTP 5xx threshold should default to 10"
  }
}

run "alerts_http_5xx_threshold_custom" {
  command = plan
  variables {
    enable_alerts            = true
    alert_http_5xx_threshold = 25
  }
  assert {
    condition     = azurerm_monitor_metric_alert.http_5xx[0].criteria[0].threshold == 25
    error_message = "HTTP 5xx threshold should be 25"
  }
}

run "alerts_response_time_threshold_default" {
  command = plan
  variables {
    enable_alerts = true
  }
  assert {
    condition     = azurerm_monitor_metric_alert.response_time[0].criteria[0].threshold == 5
    error_message = "Response time threshold should default to 5 seconds (5000ms / 1000)"
  }
}

run "alerts_response_time_threshold_custom" {
  command = plan
  variables {
    enable_alerts                    = true
    alert_response_time_threshold_ms = 10000
  }
  assert {
    condition     = azurerm_monitor_metric_alert.response_time[0].criteria[0].threshold == 10
    error_message = "Response time threshold should be 10 seconds"
  }
}

run "alerts_cpu_percentage_threshold_default" {
  command = plan
  variables {
    enable_alerts = true
  }
  assert {
    condition     = azurerm_monitor_metric_alert.cpu_percentage[0].criteria[0].threshold == 85
    error_message = "CPU percentage threshold should default to 85"
  }
}

run "alerts_cpu_percentage_threshold_custom" {
  command = plan
  variables {
    enable_alerts                  = true
    alert_cpu_percentage_threshold = 90
  }
  assert {
    condition     = azurerm_monitor_metric_alert.cpu_percentage[0].criteria[0].threshold == 90
    error_message = "CPU percentage threshold should be 90"
  }
}

run "alerts_memory_percentage_threshold_default" {
  command = plan
  variables {
    enable_alerts = true
  }
  assert {
    condition     = azurerm_monitor_metric_alert.memory_percentage[0].criteria[0].threshold == 85
    error_message = "Memory percentage threshold should default to 85"
  }
}

run "alerts_memory_percentage_threshold_custom" {
  command = plan
  variables {
    enable_alerts                     = true
    alert_memory_percentage_threshold = 95
  }
  assert {
    condition     = azurerm_monitor_metric_alert.memory_percentage[0].criteria[0].threshold == 95
    error_message = "Memory percentage threshold should be 95"
  }
}

run "alerts_health_check_not_created_without_path" {
  command = plan
  variables {
    enable_alerts = true
  }
  assert {
    condition     = length(azurerm_monitor_metric_alert.health_check) == 0
    error_message = "Health check alert should not be created without health check path"
  }
}

run "alerts_health_check_created_with_path" {
  command = plan
  variables {
    enable_alerts     = true
    health_check_path = "/health"
  }
  assert {
    condition     = length(azurerm_monitor_metric_alert.health_check) == 1
    error_message = "Health check alert should be created with health check path"
  }
}

# =============================================================================
# OUTPUT TESTS
# =============================================================================

run "output_app_service_name" {
  command = plan
  assert {
    condition     = output.app_service_name == "my-test-app"
    error_message = "app_service_name output should be 'my-test-app'"
  }
}

run "output_service_plan_name" {
  command = plan
  assert {
    condition     = output.service_plan_name == "my-test-app-plan"
    error_message = "service_plan_name output should be 'my-test-app-plan'"
  }
}

run "output_staging_slot_null_when_disabled" {
  command = plan
  assert {
    condition     = output.staging_slot_id == null
    error_message = "staging_slot_id should be null when staging slot is disabled"
  }
}

run "output_custom_domain_null_when_disabled" {
  command = plan
  assert {
    condition     = output.custom_domain_fqdn == null
    error_message = "custom_domain_fqdn should be null when custom domain is disabled"
  }
}

run "output_application_insights_null_when_disabled" {
  command = plan
  assert {
    condition     = output.application_insights_id == null
    error_message = "application_insights_id should be null when Application Insights is disabled"
  }
}

run "output_identity_principal_null_when_disabled" {
  command = plan
  assert {
    condition     = output.app_service_identity_principal_id == null
    error_message = "app_service_identity_principal_id should be null when identity is disabled"
  }
}
