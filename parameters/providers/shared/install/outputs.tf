output "storage_configuration" {
  description = "Provider specification ID plus the per-instance provider configs (id, nrn, dimensions), keyed by instance key."
  value = {
    specification_id = nullplatform_provider_specification.parameter_storage_specification.id
    instances = {
      for key, instance in var.instances : key => {
        id         = module.parameter_storage_instance[key].provider_config_id
        nrn        = instance.nrn
        dimensions = instance.dimensions
      }
    }
  }
}

output "notification_channels" {
  description = "Map of instance key => ID of its agent notification channel. Only includes instances with notification_channel_enabled=true."
  value       = { for key, channel in nullplatform_notification_channel.from_template : key => { id : channel.id, nrn : channel.nrn } }
}