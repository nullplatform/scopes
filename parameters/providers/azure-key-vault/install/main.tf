################################################################################
# Azure Key Vault — install module
#
# Two responsibilities, one source of truth:
#
#   1. nullplatform_provider_specification.this
#      Created from ../azure-key-vault-configuration.json.tpl. The JSON file
#      is the canonical declaration of the provider's metadata and its config
#      schema (vault_name).
#
#   2. module.scope_configuration (for_each = var.instances)
#      One concrete instance per entry in var.instances, each with its own
#      NRN, dimensions, and Key Vault name — so operators can route different
#      accounts/environments to different Key Vaults.
################################################################################

locals {
  template_path     = "${path.module}/../azure-key-vault-configuration.json.tpl"
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
    vault_name = each.value.vault_name
  }

  depends_on = [nullplatform_provider_specification.this]
}
