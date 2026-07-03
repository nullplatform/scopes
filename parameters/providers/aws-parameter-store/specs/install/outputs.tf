output "parameter_store_storage_configuration" {
  description = "Provider specification ID plus the per-instance provider configs (id, nrn, dimensions), keyed by instance key."
  value       = module.parameter_store.storage_configuration
}

output "notification_channels" {
  description = "Map of instance key => ID of its agent notification channel. Only includes instances with notification_channel_enabled=true."
  value       = module.parameter_store.notification_channels
}