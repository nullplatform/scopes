output "network_full_domain" {
  description = "Full domain name (subdomain.domain or just domain)"
  value       = local.network_full_domain
}

output "network_fqdn" {
  description = "Fully qualified domain name"
  value       = local.hosting_record_type == "A" ? aws_route53_record.main_alias[0].fqdn : aws_route53_record.main_cname[0].fqdn
}

output "network_website_url" {
  description = "Website URL"
  value       = "https://${local.network_full_domain}"
}