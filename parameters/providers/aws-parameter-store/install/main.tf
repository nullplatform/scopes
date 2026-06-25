################################################################################
# AWS Parameter Store — install module
#
# Two responsibilities, one source of truth:
#
#   1. nullplatform_provider_specification.this
#      Created from ../aws-parameter-store-configuration.json.tpl. The JSON
#      file is the canonical declaration of the provider's metadata and its
#      config schema (kms_key_id, tier).
#
#   2. module.scope_configuration (for_each = var.instances)
#      One concrete instance per entry in var.instances, each with its own
#      NRN, dimensions, KMS key, and tier — so operators can mix Standard and
#      Advanced tiers across accounts, or install Parameter Store only on
#      selected environments.
################################################################################

locals {
  template_path     = "${path.module}/../aws-parameter-store-configuration.json.tpl"
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
    kms_key_id = each.value.kms_key_id
    tier       = each.value.tier
  }

  depends_on = [nullplatform_provider_specification.this]
}
