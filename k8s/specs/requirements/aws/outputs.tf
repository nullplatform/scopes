output "permissions_role_arn" {
  description = "ARN of the permissions role assumed by the nullplatform agent role"
  value       = local.iam_create ? aws_iam_role.nullplatform_agent_permissions[0].arn : ""
}

output "permissions_role_name" {
  description = "Name of the permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_agent_permissions[0].name : ""
}

output "permissions_role_id" {
  description = "ID of the permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_agent_permissions[0].id : ""
}
