locals {
  # The configuration template uses gomplate-style `{{ env.Getenv "NRN" }}` for
  # `visible_to` because it's also consumed by non-tofu install paths. The only
  # token in the file is NRN, so we replace it inline rather than pulling in
  # gomplate as a build dependency.
  template_path     = "${path.module}/aws-secrets-manager-configuration.json.tpl"
  template_raw      = file(local.template_path)
  template_rendered = replace(local.template_raw, "{{ env.Getenv \"NRN\" }}", var.nrn)
  config            = jsondecode(local.template_rendered)
  cmdline_path      = "nullplatform/scopes/parameters/entrypoint"

  # The spec must be visible to the anchor NRN and to every NRN where an
  # instance lives — otherwise the instance can't reference its own spec.
  instance_nrns = distinct([for _, inst in var.instances : inst.nrn])
  spec_visible_to = distinct(concat(
    [var.nrn],
    local.instance_nrns,
    var.extra_visible_to_nrns,
  ))

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
    Sid    = "ManageNullplatformSecrets"
    Effect = "Allow"
    Action = [
      "secretsmanager:CreateSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DeleteSecret",
    ]
    Resource = "arn:aws:secretsmanager:${local.aws_region}:${local.aws_account_id}:secret:nullplatform/*"
  }

  kms_policy_statement = {
    Sid    = "UseCustomerManagedKmsKey"
    Effect = "Allow"
    Action = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    Resource = var.iam_role.kms_key_arn
    Condition = {
      StringEquals = {
        "kms:ViaService" = "secretsmanager.${local.aws_region}.amazonaws.com"
      }
    }
  }

  # Build the policy JSON conditionally at the string level — Terraform's strict
  # typing rejects ternaries that return tuples of differently-shaped objects
  # (base has 4 keys, kms statement adds Condition for the 5th).
  policy_doc = var.iam_role.mode == "with_kms" ? jsonencode({
    Version   = "2012-10-17"
    Statement = [local.base_policy_statement, local.kms_policy_statement]
    }) : jsonencode({
    Version   = "2012-10-17"
    Statement = [local.base_policy_statement]
  })

  # Instances that get their own agent API key + notification channel.
  notification_instances = {
    for key, instance in var.instances : key => instance
    if instance.notification_channel_enabled
  }

  api_key_grants = [
    "controlplane:agent",
    "developer",
    "ops",
    "secops",
    "secrets-reader",
  ]
}
