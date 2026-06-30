################################################################################
# AWS Secrets Manager — specs module
#
# Two responsibilities, one source of truth:
#
#   1. nullplatform_provider_specification.this
#      Created from ../aws-secrets-manager-configuration.json.tpl. Mirrors the
#      `from_scope_configuration` block in tofu-modules' scope_definition
#      module — the JSON file is the canonical declaration of the provider's
#      metadata (name, icon, category) and its config schema.
#
#   2. module.scope_configuration (for_each = var.instances)
#      One concrete instance per entry in var.instances, each with its own
#      NRN, dimensions, and KMS key. This is the per-account / per-environment
#      knob: operators can give prod its own KMS key, install the provider only
#      under selected accounts, or both. Delegates to the upstream
#      `nullplatform/scope_configuration` module.
################################################################################

locals {
  # The configuration template uses gomplate-style `{{ env.Getenv "NRN" }}` for
  # `visible_to` because it's also consumed by non-tofu install paths. The only
  # token in the file is NRN, so we replace it inline rather than pulling in
  # gomplate as a build dependency.
  template_path     = "${path.module}/aws-secrets-manager-configuration.json.tpl"
  template_raw      = file(local.template_path)
  template_rendered = replace(local.template_raw, "{{ env.Getenv \"NRN\" }}", var.nrn)
  config            = jsondecode(local.template_rendered)

  # The spec must be visible to the anchor NRN and to every NRN where an
  # instance lives — otherwise the instance can't reference its own spec.
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
      kms_key_id = each.value.kms_key_id
    }
  }

  depends_on = [nullplatform_provider_specification.this]
}
