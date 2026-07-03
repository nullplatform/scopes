resource "nullplatform_provider_specification" "parameter_storage_specification" {
  name             = local.config.name
  icon             = local.config.icon
  description      = local.config.description
  category         = local.config.category
  allow_dimensions = local.config.allow_dimensions
  visible_to       = local.spec_visible_to
  schema           = jsonencode(local.config.schema)
}

module "parameter_storage_instance" {
  for_each = var.instances
  source   = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_configuration?ref=v4.5.1"

  nrn                         = each.value.nrn
  np_api_key                  = var.np_api_key
  provider_specification_slug = local.config.slug
  dimensions                  = each.value.dimensions

  attributes = each.value.attributes

  depends_on = [nullplatform_provider_specification.parameter_storage_specification]
}

module "parameter_storage_api_keys" {
  source   = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/api_key?ref=v5.3.1"
  for_each = local.notification_instances

  type               = "agent"
  nrn                = each.value.nrn
  specification_slug = "parameter_storage"
}

resource "nullplatform_notification_channel" "from_template" {
  for_each = local.notification_instances

  nrn         = each.value.nrn
  type        = "agent"
  source      = ["parameters"]
  description = "Notification channel to handle parameter storage and retrieval"
  configuration {
    agent {
      api_key  = module.parameter_storage_api_keys[each.key].api_key
      selector = each.value.tags_selectors
      command {
        data = {
          "cmdline" : local.cmdline_path
          "environment" : jsonencode({
            NP_ACTION_CONTEXT = "'$${NOTIFICATION_CONTEXT}'"
            LOG_LEVEL         = "debug"
          })
        }
        type = "exec"
      }
    }
  }
}