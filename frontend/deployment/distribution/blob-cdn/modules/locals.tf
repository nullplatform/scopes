# =============================================================================
# Locals for Azure CDN Distribution
# =============================================================================

locals {
  # Use network_full_domain from network layer (provided via cross-module locals when composed)
  distribution_has_custom_domain = local.network_full_domain != ""
  distribution_full_domain       = local.network_full_domain

  # Normalize blob_prefix: trim leading/trailing slashes, then add single leading slash if non-empty
  distribution_blob_prefix_trimmed = trim(var.distribution_blob_prefix, "/")
  distribution_origin_path         = local.distribution_blob_prefix_trimmed != "" ? "/${local.distribution_blob_prefix_trimmed}" : ""

  distribution_tags = merge(var.distribution_resource_tags_json, {
    ManagedBy = "terraform"
    Module    = "distribution/blob-cdn"
  })

  # Cross-module references (consumed by network/azure_dns)
  distribution_target_domain = azurerm_cdn_endpoint.static.fqdn
  distribution_record_type   = "CNAME"
}
