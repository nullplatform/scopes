################################################################################
# AWS Parameter Store — specs module
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
  template_path     = "${path.module}/aws-parameter-store-configuration.json.tpl"
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
      kms_key_id = each.value.kms_key_id
      tier       = each.value.tier
    }
  }

  depends_on = [nullplatform_provider_specification.this]
}

################################################################################
# Optional: IAM role with least-privilege permissions for this provider.
# Toggle with var.iam_role.enable. Outputs the role ARN so operators can wire
# it into the identity-access-control provider config (selector="parameter_store").
################################################################################

data "aws_caller_identity" "current" {
  count = var.iam_role.enable ? 1 : 0
}

data "aws_region" "current" {
  count = var.iam_role.enable ? 1 : 0
}

locals {
  iam_enabled    = var.iam_role.enable
  aws_account_id = local.iam_enabled ? data.aws_caller_identity.current[0].account_id : ""
  aws_region     = local.iam_enabled ? data.aws_region.current[0].name : ""

  # If trusted_principals isn't provided, default to the current account root.
  # That allows IAM principals within the account to assume the role (subject
  # to their own IAM policies). To lock it down further, pass explicit ARNs.
  effective_trusted_principals = local.iam_enabled ? (
    length(var.iam_role.trusted_principals) > 0
    ? var.iam_role.trusted_principals
    : ["arn:aws:iam::${local.aws_account_id}:root"]
  ) : []

  base_policy_statement = {
    Sid    = "ManageNullplatformParameters"
    Effect = "Allow"
    Action = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:DeleteParameter",
    ]
    Resource = "arn:aws:ssm:${local.aws_region}:${local.aws_account_id}:parameter/nullplatform/*"
  }

  kms_policy_statement = {
    Sid    = "UseCustomerManagedKmsKey"
    Effect = "Allow"
    Action = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    Resource = var.iam_role.kms_key_arn
    Condition = {
      StringEquals = {
        "kms:ViaService" = "ssm.${local.aws_region}.amazonaws.com"
      }
    }
  }

  policy_statements = var.iam_role.mode == "with_kms" ? [local.base_policy_statement, local.kms_policy_statement] : [local.base_policy_statement]
}

resource "aws_iam_role" "this" {
  count = local.iam_enabled ? 1 : 0
  name  = var.iam_role.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = local.effective_trusted_principals
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "this" {
  count = local.iam_enabled ? 1 : 0
  name  = "${var.iam_role.name}-policy"
  role  = aws_iam_role.this[0].name

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.policy_statements
  })
}
