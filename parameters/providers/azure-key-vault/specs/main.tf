################################################################################
# Azure Key Vault — specs module
#
# Responsibilities:
#
#   1. nullplatform_provider_specification.this
#      Created from ./azure-key-vault-configuration.json.tpl. The JSON file is
#      the canonical declaration of the provider's metadata and its config
#      schema (vault_name).
#
#   2. module.scope_configuration (for_each = var.instances)
#      One concrete instance per entry in var.instances, each with its own NRN,
#      dimensions, and Key Vault name — so operators can route different
#      accounts/environments to different Key Vaults.
#
#   3. nullplatform_api_key.this + nullplatform_notification_channel.from_template
#      Per instance (unless notification_channel_enabled=false): an agent API key
#      and its notification channel, anchored at the instance NRN, that handle
#      secret storage and retrieval.
################################################################################

resource "nullplatform_provider_specification" "this" {
  name             = local.config.name
  icon             = local.config.icon
  description      = local.config.description
  category         = local.config.category
  allow_dimensions = local.config.allow_dimensions
  visible_to       = local.spec_visible_to
  schema           = jsonencode(local.config.schema)
}

module "scope_configuration" {
  for_each = var.instances
  source   = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_configuration?ref=v4.5.1"

  nrn                         = each.value.nrn
  np_api_key                  = var.np_api_key
  provider_specification_slug = local.config.slug
  dimensions                  = each.value.dimensions

  attributes = {
    sensibility = {
      applies_to = each.value.applies_to
    }
    setup = {
      vault_name = each.value.vault_name
    }
  }

  depends_on = [nullplatform_provider_specification.this]
}

resource "nullplatform_api_key" "this" {
  for_each = local.notification_instances

  name = "azure-key-vault-api-key-${each.key}"
  dynamic "grants" {
    for_each = toset(local.api_key_grants)
    content {
      nrn       = each.value.nrn
      role_slug = grants.value
    }
  }

  tags {
    key   = "managedBy"
    value = "IaC"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "nullplatform_notification_channel" "from_template" {
  for_each = local.notification_instances

  nrn         = each.value.nrn
  type        = "agent"
  source      = ["parameters"]
  description = "Notification channel to handle parameter storage and retrieval"
  configuration {
    agent {
      api_key  = nullplatform_api_key.this[each.key].api_key
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
