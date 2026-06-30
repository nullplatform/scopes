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
  description = "Provider instances to create. Map key is a stable identifier (used in for_each). Each entry carries its own NRN, dimensions, KMS key (for SecureString), tier, and the parameter sensibility set this instance handles (secret / non_secret / both)."
  type = map(object({
    nrn        = string
    dimensions = map(string)
    kms_key_id = string
    tier       = string
    applies_to = list(string)
  }))
  default = {}
}

variable "iam_role" {
  description = <<-EOT
    Optionally create the AWS IAM role with least-privilege permissions this provider needs.
    Fields:
      enable             — set true to create the role + inline policy.
      name               — role name (required when enable=true).
      mode               — "default" (ssm + default KMS) or "with_kms" (adds customer-managed KMS perms).
      trusted_principals — list of ARNs allowed to assume the role. Defaults to the current account root
                           (any principal in the account, further controlled by their own IAM policies).
      kms_key_arn        — required when mode="with_kms". The customer-managed KMS key the role can use.
    The role's ARN is exposed via the `iam_role_arn` output so operators can plug it into the
    identity-access-control provider's iam_role_arns.arns[].arn field with selector="parameter_store".
  EOT
  type = object({
    enable             = bool
    name               = string
    mode               = optional(string, "default")
    trusted_principals = optional(list(string), [])
    kms_key_arn        = optional(string, "")
  })
  default = {
    enable = false
    name   = ""
  }

  validation {
    condition     = !var.iam_role.enable || var.iam_role.name != ""
    error_message = "iam_role.name is required when iam_role.enable=true."
  }

  validation {
    condition     = !var.iam_role.enable || contains(["default", "with_kms"], var.iam_role.mode)
    error_message = "iam_role.mode must be \"default\" or \"with_kms\"."
  }

  validation {
    condition     = !var.iam_role.enable || var.iam_role.mode != "with_kms" || var.iam_role.kms_key_arn != ""
    error_message = "iam_role.kms_key_arn is required when iam_role.enable=true and iam_role.mode=\"with_kms\"."
  }
}
