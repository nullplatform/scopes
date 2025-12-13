output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_branch" {
  value = aws_amplify_branch.tag.branch_name
}

output "public_url" {
  value = "https://${var.subdomain}.${var.domain}"
}


output "amplify_dns_instructions" {
  value = aws_amplify_domain_association.domain_association.sub_domain
}