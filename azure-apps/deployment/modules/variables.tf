# =============================================================================
# CORE CONFIGURATION
# =============================================================================

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "app_name" {
  description = "Name of the App Service (must be globally unique)"
  type        = string
}

variable "resource_tags" {
  description = "Resource tags as map"
  type        = map(string)
  default     = {}
}

variable "parameter_json" {
  description = "JSON object with environment variables for the application"
  type        = string
  default     = "{}"
}

# =============================================================================
# APP SERVICE PLAN
# =============================================================================

variable "service_plan_name" {
  description = "Name of the App Service Plan (defaults to app_name-plan)"
  type        = string
  default     = ""
}

variable "sku_name" {
  description = "SKU for the App Service Plan (B1, B2, B3, S1, S2, S3, P1v2, P2v2, P3v2, P1v3, P2v3, P3v3)"
  type        = string
  default     = "S1"
}

variable "os_type" {
  description = "OS type for the App Service Plan (Linux or Windows)"
  type        = string
  default     = "Linux"
}

variable "per_site_scaling_enabled" {
  description = "Enable per-app scaling (allows different apps on same plan to scale independently)"
  type        = bool
  default     = false
}

variable "zone_balancing_enabled" {
  description = "Enable zone redundancy for the App Service Plan"
  type        = bool
  default     = false
}

# =============================================================================
# DOCKER / CONTAINER CONFIGURATION
# =============================================================================

variable "docker_image" {
  description = "Docker image name with tag (e.g., myapp:latest)"
  type        = string
}

variable "docker_registry_url" {
  description = "Docker registry URL (e.g., https://index.docker.io, https://myregistry.azurecr.io)"
  type        = string
  default     = "https://index.docker.io"
}

variable "docker_registry_username" {
  description = "Docker registry username (leave empty for public images or managed identity)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "docker_registry_password" {
  description = "Docker registry password (leave empty for public images or managed identity)"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# APP SERVICE CONFIGURATION
# =============================================================================

variable "always_on" {
  description = "Keep the app always loaded (prevents cold starts, requires Basic+ tier)"
  type        = bool
  default     = true
}

variable "https_only" {
  description = "Redirect all HTTP traffic to HTTPS"
  type        = bool
  default     = true
}

variable "http2_enabled" {
  description = "Enable HTTP/2 protocol"
  type        = bool
  default     = true
}

variable "websockets_enabled" {
  description = "Enable WebSocket support"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Path for health check endpoint (e.g., /health)"
  type        = string
  default     = ""
}

variable "health_check_eviction_time_in_min" {
  description = "Time in minutes before an unhealthy instance is removed"
  type        = number
  default     = 10
}

variable "ftps_state" {
  description = "FTPS state (AllAllowed, FtpsOnly, Disabled)"
  type        = string
  default     = "Disabled"
}

variable "minimum_tls_version" {
  description = "Minimum TLS version (1.0, 1.1, 1.2)"
  type        = string
  default     = "1.2"
}

variable "client_affinity_enabled" {
  description = "Enable ARR affinity (sticky sessions)"
  type        = bool
  default     = false
}

variable "app_command_line" {
  description = "Startup command for the container"
  type        = string
  default     = ""
}

# =============================================================================
# DEPLOYMENT SLOTS
# =============================================================================

variable "enable_staging_slot" {
  description = "Create a staging deployment slot"
  type        = bool
  default     = false
}

variable "staging_slot_name" {
  description = "Name of the staging slot"
  type        = string
  default     = "staging"
}

variable "staging_slot_always_on" {
  description = "Keep the staging slot always loaded"
  type        = bool
  default     = false
}

variable "staging_traffic_percent" {
  description = "Percentage of traffic to route to staging slot (0-100). Used for gradual traffic shifting during blue-green deployments."
  type        = number
  default     = 0

  validation {
    condition     = var.staging_traffic_percent >= 0 && var.staging_traffic_percent <= 100
    error_message = "staging_traffic_percent must be between 0 and 100"
  }
}

variable "promote_staging_to_production" {
  description = "When true, performs a slot swap promoting staging to production. After swap, the previous production becomes staging."
  type        = bool
  default     = false
}

# =============================================================================
# DNS / CUSTOM DOMAIN
# =============================================================================

variable "enable_custom_domain" {
  description = "Enable custom domain configuration"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Name of the Azure DNS zone (e.g., example.com)"
  type        = string
  default     = ""
}

variable "dns_zone_resource_group" {
  description = "Resource group containing the DNS zone"
  type        = string
  default     = ""
}

variable "custom_subdomain" {
  description = "Subdomain for the app (e.g., 'api' for api.example.com, or '@' for apex domain)"
  type        = string
  default     = "@"
}

variable "enable_managed_certificate" {
  description = "Enable free Azure-managed SSL certificate for custom domain"
  type        = bool
  default     = true
}

# =============================================================================
# LOGGING
# =============================================================================

variable "enable_logging" {
  description = "Enable application and HTTP logging"
  type        = bool
  default     = true
}

variable "application_logs_level" {
  description = "Application log level (Off, Error, Warning, Information, Verbose)"
  type        = string
  default     = "Information"
}

variable "http_logs_retention_days" {
  description = "HTTP logs retention in days"
  type        = number
  default     = 7
}

variable "http_logs_retention_mb" {
  description = "HTTP logs retention in MB"
  type        = number
  default     = 35
}

variable "detailed_error_messages" {
  description = "Enable detailed error messages in logs"
  type        = bool
  default     = true
}

variable "failed_request_tracing" {
  description = "Enable failed request tracing"
  type        = bool
  default     = true
}

# =============================================================================
# APPLICATION INSIGHTS / MONITORING
# =============================================================================

variable "enable_application_insights" {
  description = "Enable Application Insights for APM"
  type        = bool
  default     = false
}

variable "application_insights_name" {
  description = "Name for Application Insights resource (defaults to app_name-insights)"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name" {
  description = "Name for Log Analytics Workspace (defaults to app_name-logs)"
  type        = string
  default     = ""
}

variable "log_analytics_retention_days" {
  description = "Log Analytics data retention in days"
  type        = number
  default     = 30
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings to export logs to Log Analytics"
  type        = bool
  default     = false
}

# =============================================================================
# AUTOSCALING
# =============================================================================

variable "enable_autoscaling" {
  description = "Enable autoscaling for the App Service Plan"
  type        = bool
  default     = false
}

variable "autoscale_min_instances" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "autoscale_max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "autoscale_default_instances" {
  description = "Default number of instances"
  type        = number
  default     = 2
}

variable "cpu_scale_out_threshold" {
  description = "CPU percentage to trigger scale out"
  type        = number
  default     = 70
}

variable "cpu_scale_in_threshold" {
  description = "CPU percentage to trigger scale in"
  type        = number
  default     = 30
}

variable "memory_scale_out_threshold" {
  description = "Memory percentage to trigger scale out"
  type        = number
  default     = 75
}

variable "memory_scale_in_threshold" {
  description = "Memory percentage to trigger scale in"
  type        = number
  default     = 40
}

variable "scale_out_cooldown" {
  description = "Cooldown period after scale out (ISO 8601 duration, e.g., PT5M)"
  type        = string
  default     = "PT5M"
}

variable "scale_in_cooldown" {
  description = "Cooldown period after scale in (ISO 8601 duration, e.g., PT10M)"
  type        = string
  default     = "PT10M"
}

variable "autoscale_notification_emails" {
  description = "Email addresses to notify on autoscale events"
  type        = list(string)
  default     = []
}

# =============================================================================
# AUTO-HEAL
# =============================================================================

variable "enable_auto_heal" {
  description = "Enable auto-heal to automatically restart unhealthy instances"
  type        = bool
  default     = false
}

variable "auto_heal_slow_request_count" {
  description = "Number of slow requests to trigger auto-heal"
  type        = number
  default     = 10
}

variable "auto_heal_slow_request_interval" {
  description = "Interval for counting slow requests (ISO 8601 duration)"
  type        = string
  default     = "00:01:00"
}

variable "auto_heal_slow_request_time_taken" {
  description = "Time threshold for a request to be considered slow (ISO 8601 duration)"
  type        = string
  default     = "00:00:30"
}

variable "auto_heal_status_code_count" {
  description = "Number of error status codes to trigger auto-heal"
  type        = number
  default     = 50
}

variable "auto_heal_status_code_interval" {
  description = "Interval for counting error status codes (ISO 8601 duration)"
  type        = string
  default     = "00:05:00"
}

variable "auto_heal_status_code_range" {
  description = "Status code range to monitor (e.g., 500-599)"
  type        = string
  default     = "500-599"
}

variable "auto_heal_min_process_time" {
  description = "Minimum process execution time before auto-heal can trigger (ISO 8601 duration)"
  type        = string
  default     = "00:01:00"
}

# =============================================================================
# NETWORKING
# =============================================================================

variable "enable_vnet_integration" {
  description = "Enable VNet integration"
  type        = bool
  default     = false
}

variable "vnet_integration_subnet_id" {
  description = "Subnet ID for VNet integration"
  type        = string
  default     = ""
}

variable "vnet_route_all_enabled" {
  description = "Route all outbound traffic through VNet"
  type        = bool
  default     = false
}

variable "ip_restriction_default_action" {
  description = "Default action for IP restrictions (Allow or Deny)"
  type        = string
  default     = "Allow"
}

variable "ip_restrictions" {
  description = "List of IP restrictions"
  type = list(object({
    name        = string
    ip_address  = optional(string)
    service_tag = optional(string)
    priority    = number
    action      = string
  }))
  default = []
}

# =============================================================================
# IDENTITY
# =============================================================================

variable "enable_system_identity" {
  description = "Enable system-assigned managed identity"
  type        = bool
  default     = false
}

variable "user_assigned_identity_ids" {
  description = "List of user-assigned managed identity IDs"
  type        = list(string)
  default     = []
}

# =============================================================================
# ALERTING
# =============================================================================

variable "enable_alerts" {
  description = "Enable Azure Monitor alerts"
  type        = bool
  default     = false
}

variable "alert_email_recipients" {
  description = "Email addresses to receive alerts"
  type        = list(string)
  default     = []
}

variable "alert_http_5xx_threshold" {
  description = "Threshold for HTTP 5xx alert"
  type        = number
  default     = 10
}

variable "alert_response_time_threshold_ms" {
  description = "Threshold for response time alert in milliseconds"
  type        = number
  default     = 5000
}

variable "alert_cpu_percentage_threshold" {
  description = "Threshold for CPU percentage alert"
  type        = number
  default     = 85
}

variable "alert_memory_percentage_threshold" {
  description = "Threshold for memory percentage alert"
  type        = number
  default     = 85
}
