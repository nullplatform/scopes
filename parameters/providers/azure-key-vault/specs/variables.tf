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
  description = "Provider instances to create. Map key is a stable identifier (used in for_each). Each entry carries its own NRN, dimensions, Azure Key Vault name, and the parameter sensibility set this instance handles (secret / non_secret / both)."
  type = map(object({
    nrn        = string
    dimensions = map(string)
    vault_name = string
    applies_to = list(string)
  }))
  default = {}
}
