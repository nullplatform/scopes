# =============================================================================
# Test-only locals
#
# This file provides the network_* locals that are normally defined by the
# network layer (Route53, etc.) when modules are composed.
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

locals {
  # These locals are normally provided by network modules (e.g., Route53)
  # For testing, we bridge from variables to locals
  network_full_domain = var.network_full_domain
  network_domain      = var.network_domain
}
