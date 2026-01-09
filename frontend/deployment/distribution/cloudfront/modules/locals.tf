locals {
  distribution_origin_id       = "S3-${var.distribution_bucket_name}"
  distribution_aws_endpoint_url_param = var.distribution_cloudfront_endpoint_url != "" ? "--endpoint-url ${var.distribution_cloudfront_endpoint_url}" : ""

  # Use network_full_domain from network layer (provided via cross-module locals when composed)
  distribution_aliases = local.network_full_domain != "" ? [local.network_full_domain] : []

  # Normalize s3_prefix: trim leading/trailing slashes, then add single leading slash if non-empty
  distribution_s3_prefix_trimmed = trim(var.distribution_s3_prefix, "/")
  distribution_origin_path       = local.distribution_s3_prefix_trimmed != "" ? "/${local.distribution_s3_prefix_trimmed}" : ""

  # ACM certificate domain: derive wildcard from network_domain
  # e.g., "example.com" -> "*.example.com"
  distribution_acm_certificate_domain = local.network_domain != "" ? "*.${local.network_domain}" : ""
  distribution_has_acm_certificate    = length(data.aws_acm_certificate.custom_domain) > 0

  distribution_default_tags = merge(var.distribution_resource_tags_json, {
    ManagedBy = "terraform"
    Module    = "distribution/cloudfront"
  })

  # Cross-module references (consumed by network/route53)
  distribution_target_domain  = aws_cloudfront_distribution.static.domain_name
  distribution_target_zone_id = aws_cloudfront_distribution.static.hosted_zone_id
  distribution_record_type    = "A"
}