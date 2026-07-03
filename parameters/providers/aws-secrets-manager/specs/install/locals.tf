locals {
  # Shape each operator-facing instance into the generic `attributes` object the
  # shared module forwards to the provider spec. Secrets Manager's schema carries
  # sensibility.applies_to plus setup.kms_key_id (no tier, unlike Parameter Store).
  instances = {
    for key, instance in var.instances : key => {
      nrn                          = instance.nrn
      dimensions                   = instance.dimensions
      notification_channel_enabled = instance.notification_channel_enabled
      tags_selectors               = instance.tags_selectors
      attributes = {
        sensibility = {
          applies_to = instance.applies_to
        }
        setup = {
          kms_key_id = instance.kms_key_id
        }
      }
    }
  }
}
