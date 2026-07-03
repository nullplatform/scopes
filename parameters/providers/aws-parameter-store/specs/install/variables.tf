variable "nrn" {
  description = "NRN where the provider specification is anchored (the top-level scope it belongs to)."
  type        = string
}

variable "np_api_key" {
  description = "nullplatform API key used by the upstream scope_configuration module to register provider instances."
  type        = string
  sensitive   = true
}

variable "extra_visible_to_nrns" {
  description = "Additional NRNs that should see the provider specification besides var.nrn and the per-instance NRNs."
  type        = list(string)
  default     = []
}

variable "instances" {
  description = <<-EOT
    Provider instances to create. Map key is a stable identifier (used in for_each).
    Each entry carries its own NRN, dimensions, KMS key (for SecureString), tier, and the
    parameter sensibility set this instance handles (secret / non_secret / both).
    Each instance also gets its own agent API key + notification channel (anchored at the
    instance NRN) unless notification_channel_enabled=false. Fields:
      notification_channel_enabled — create the agent channel + its API key for this instance (default true).
      tags_selectors               — tag key/value pairs the agent uses to match this instance's channel
                                      against scope tags (e.g. { environment = "development" }).
  EOT
  type = map(object({
    nrn                          = string
    dimensions                   = map(string)
    kms_key_id                   = string
    tier                         = string
    applies_to                   = list(string)
    notification_channel_enabled = optional(bool, true)
    tags_selectors               = optional(map(string), {})
  }))
  default = {}
}