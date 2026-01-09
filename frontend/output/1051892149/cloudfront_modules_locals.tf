locals {
  distribution_origin_id = "S3-${var.distribution_bucket_name}"
  distribution_aliases   = var.distribution_custom_domain != null ? [var.distribution_custom_domain] : []

  distribution_default_tags = merge(var.distribution_resource_tags_json, {
    ManagedBy = "terraform"
    Module    = "distribution/cloudfront"
  })

  # Cross-module references (consumed by network/route53)
  distribution_target_domain  = aws_cloudfront_distribution.static.domain_name
  distribution_target_zone_id = aws_cloudfront_distribution.static.hosted_zone_id
  distribution_record_type    = "A"
}
