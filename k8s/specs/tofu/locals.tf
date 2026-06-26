locals {
  # Module identifier
  iam_module_name = "iam"

  # Whether resources are created
  iam_create = var.iam_create_role

  # Derived names (overridable via variables)
  permissions_role_name = var.permissions_role_name != "" ? var.permissions_role_name : "nullplatform-${var.cluster_name}-agent-permissions-role"
  policies_name_prefix  = var.policies_name_prefix != "" ? var.policies_name_prefix : "nullplatform_${var.cluster_name}"

  # Default tags applied to every IAM resource
  iam_default_tags = merge(var.iam_resource_tags_json, {
    ManagedBy = "nullplatform-custom-scope-role"
    Module    = local.iam_module_name
  })
}
