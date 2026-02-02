output "distribution_bucket_name" {
  description = "S3 bucket name"
  value       = data.aws_s3_bucket.static.id
}

output "distribution_bucket_arn" {
  description = "S3 bucket ARN"
  value       = data.aws_s3_bucket.static.arn
}

output "distribution_s3_prefix" {
  description = "S3 prefix path for this scope"
  value       = var.distribution_s3_prefix
}

output "distribution_cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.static.id
}

output "distribution_cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = aws_cloudfront_distribution.static.domain_name
}

output "distribution_target_domain" {
  description = "Target domain for DNS records (CloudFront domain)"
  value       = local.distribution_target_domain
}

output "distribution_target_zone_id" {
  description = "Hosted zone ID for Route 53 alias records"
  value       = local.distribution_target_zone_id
}

output "distribution_record_type" {
  description = "DNS record type (A for CloudFront alias)"
  value       = local.distribution_record_type
}

output "distribution_website_url" {
  description = "Website URL"
  value       = local.network_full_domain != "" ? "https://${local.network_full_domain}" : "https://${aws_cloudfront_distribution.static.domain_name}"
}