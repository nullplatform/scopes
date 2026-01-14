# =============================================================================
# Test-only locals
#
# This file provides the distribution_* locals that are normally defined by the
# distribution layer (CloudFront, Amplify, etc.) when modules are composed.
# This file is only used for running isolated unit tests.
#
# NOTE: Files matching test_*.tf are skipped by compose_modules
# =============================================================================

# Test-only variables to allow tests to control the hosting values
variable "distribution_target_domain" {
  description = "Test-only: Target domain from hosting provider"
  type        = string
  default     = "d1234567890.cloudfront.net"
}

variable "distribution_target_zone_id" {
  description = "Test-only: Hosted zone ID from hosting provider"
  type        = string
  default     = "Z2FDTNDATAQYW2"
}

variable "distribution_record_type" {
  description = "Test-only: DNS record type (A or CNAME)"
  type        = string
  default     = "A"
}

locals {
  # These locals are normally provided by distribution modules (e.g., CloudFront)
  # For testing, we bridge from variables to locals
  distribution_target_domain  = var.distribution_target_domain
  distribution_target_zone_id = var.distribution_target_zone_id
  distribution_record_type    = var.distribution_record_type
}
