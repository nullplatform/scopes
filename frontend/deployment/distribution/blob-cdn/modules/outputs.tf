output "distribution_storage_account" {
  description = "Azure Storage account name"
  value       = var.distribution_storage_account
}

output "distribution_container_name" {
  description = "Azure Storage container name"
  value       = var.distribution_container_name
}

output "distribution_blob_prefix" {
  description = "Blob prefix path for this scope"
  value       = var.distribution_blob_prefix
}

output "distribution_cdn_profile_name" {
  description = "Azure CDN profile name"
  value       = azurerm_cdn_profile.static.name
}

output "distribution_cdn_endpoint_name" {
  description = "Azure CDN endpoint name"
  value       = azurerm_cdn_endpoint.static.name
}

output "distribution_cdn_endpoint_hostname" {
  description = "Azure CDN endpoint hostname"
  value       = azurerm_cdn_endpoint.static.fqdn
}

output "distribution_target_domain" {
  description = "Target domain for DNS records (CDN endpoint hostname)"
  value       = local.distribution_target_domain
}

output "distribution_record_type" {
  description = "DNS record type (CNAME for Azure CDN)"
  value       = local.distribution_record_type
}

output "distribution_website_url" {
  description = "Website URL"
  value       = local.distribution_has_custom_domain ? "https://${local.distribution_full_domain}" : "https://${azurerm_cdn_endpoint.static.fqdn}"
}
