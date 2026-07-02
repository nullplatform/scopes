output "specification_id" {
  description = "ID of the nullplatform_provider_specification created from aws-secrets-manager-configuration.json.tpl."
  value       = nullplatform_provider_specification.this.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role created when iam_role.enable=true. Wire this into the identity-access-control provider's iam_role_arns.arns[] with selector=\"secret_manager\". Empty when iam_role.enable=false."
  value       = length(aws_iam_role.this) > 0 ? aws_iam_role.this[0].arn : ""
}

output "notification_channel_ids" {
  description = "Map of instance key => ID of its agent notification channel. Only includes instances with notification_channel_enabled=true."
  value       = { for key, channel in nullplatform_notification_channel.from_template : key => channel.id }
}

output "notification_channel_statuses" {
  description = "Map of instance key => status of its agent notification channel. Only includes instances with notification_channel_enabled=true."
  value       = { for key, channel in nullplatform_notification_channel.from_template : key => channel.status }
}
