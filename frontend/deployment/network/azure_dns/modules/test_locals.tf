# =============================================================================
# Test-only locals
#
# This file provides the distribution_* locals that are normally defined by the
# distribution layer (blob-cdn, etc.) when modules are composed.
# This file is only used for running isolated unit tests.
#
# NOTE: Files matching test_*.tf are skipped by compose_modules
# =============================================================================

# Test-only variables to allow tests to control the distribution values
variable "distribution_target_domain" {
  description = "Test-only: Target domain from distribution provider"
  type        = string
  default     = "myapp.azureedge.net"
}

variable "distribution_record_type" {
  description = "Test-only: DNS record type (A or CNAME)"
  type        = string
  default     = "CNAME"
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
  # These locals are normally provided by distribution modules (e.g., blob-cdn)
  # For testing, we bridge from variables to locals
  distribution_target_domain = var.distribution_target_domain
  distribution_record_type   = var.distribution_record_type
}
