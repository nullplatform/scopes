variable "agent_role_arn" {
  description = "ARN of the nullplatform agent IRSA role allowed to assume this permissions role via sts:AssumeRole. This is the trusted principal of the role's trust policy."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.agent_role_arn))
    error_message = "agent_role_arn must match arn:aws:iam::<account-id>:role/<role-name>"
  }
}

variable "cluster_name" {
  description = "Name of the cluster where the agent runs. Used to derive default resource names."
  type        = string
}

variable "permissions_role_name" {
  description = "Override for the permissions IAM role name. Defaults to nullplatform-{cluster_name}-agent-permissions-role."
  type        = string
  default     = ""
}

variable "policies_name_prefix" {
  description = "Override for the IAM policy name prefix. Defaults to nullplatform_{cluster_name}."
  type        = string
  default     = ""
}

variable "iam_create_role" {
  description = "Whether to create the permissions role and its policies. When false, the module produces no resources."
  type        = bool
  default     = true
}

variable "iam_resource_tags_json" {
  description = "Tags to apply to IAM resources created by this module."
  type        = map(string)
  default     = {}
}
