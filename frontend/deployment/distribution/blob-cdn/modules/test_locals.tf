# =============================================================================
# Test-only locals
#
# This file provides the network_* locals that are normally defined by the
# network layer (Azure DNS, etc.) when modules are composed.
# This file is only used for running isolated unit tests.
#
# NOTE: Files matching test_*.tf are skipped by compose_modules
# =============================================================================

# Test-only variables to allow tests to control the network values
variable "network_full_domain" {
  description = "Test-only: Full domain from network layer (e.g., app.example.com)"
  type        = string
  default     = ""
}

variable "network_domain" {
  description = "Test-only: Root domain from network layer (e.g., example.com)"
  type        = string
  default     = ""
}

variable "network_dns_zone_name" {
  description = "Azure DNS zone name"
  type        = string
  default     = ""
}

variable "network_subdomain" {
  description = "Subdomain for the distribution"
  type        = string
  default     = ""
}

variable "azure_provider" {
  description = "Azure provider configuration"
  type = object({
    subscription_id = string
    resource_group  = string
    storage_account = string
    container       = string
  })
}

locals {
  # These locals are normally provided by network modules (e.g., Azure DNS)
  # For testing, we bridge from variables to locals
  network_full_domain = var.network_full_domain
  network_domain      = var.network_domain
}
