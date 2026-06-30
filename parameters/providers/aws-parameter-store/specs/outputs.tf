output "specification_id" {
  description = "ID of the nullplatform_provider_specification created from aws-parameter-store-configuration.json.tpl."
  value       = nullplatform_provider_specification.this.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role created when iam_role.enable=true. Wire this into the identity-access-control provider's iam_role_arns.arns[] with selector=\"parameter_store\". Empty when iam_role.enable=false."
  value       = length(aws_iam_role.this) > 0 ? aws_iam_role.this[0].arn : ""
}
