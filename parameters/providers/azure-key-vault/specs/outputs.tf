output "specification_id" {
  description = "ID of the nullplatform_provider_specification created from azure-key-vault-configuration.json.tpl."
  value       = nullplatform_provider_specification.this.id
}

output "notification_channel_ids" {
  description = "Map of instance key => ID of its agent notification channel. Only includes instances with notification_channel_enabled=true."
  value       = { for key, channel in nullplatform_notification_channel.from_template : key => channel.id }
}

output "notification_channel_statuses" {
  description = "Map of instance key => status of its agent notification channel. Only includes instances with notification_channel_enabled=true."
  value       = { for key, channel in nullplatform_notification_channel.from_template : key => channel.status }
}
