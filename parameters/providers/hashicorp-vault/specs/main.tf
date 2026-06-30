################################################################################
# HashiCorp Vault — specs module
#
# Two responsibilities, one source of truth:
#
#   1. nullplatform_provider_specification.this
#      Created from ../hashicorp-vault-configuration.json.tpl. The JSON file
#      is the canonical declaration of the provider's metadata and its config
#      schema (address).
#
#   2. module.scope_configuration (for_each = var.instances)
#      One concrete instance per entry in var.instances, each with its own
#      NRN, dimensions, and Vault address — so operators can point different
#      accounts/environments at different Vault clusters.
################################################################################

locals {
  template_path     = "${path.module}/hashicorp-vault-configuration.json.tpl"
  template_raw      = file(local.template_path)
  template_rendered = replace(local.template_raw, "{{ env.Getenv \"NRN\" }}", var.nrn)
  config            = jsondecode(local.template_rendered)

  instance_nrns = distinct([for _, inst in var.instances : inst.nrn])
  spec_visible_to = distinct(concat(
    [var.nrn],
    local.instance_nrns,
    var.extra_visible_to_nrns,
  ))
}

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
      address = each.value.address
    }
  }

  depends_on = [nullplatform_provider_specification.this]
}
