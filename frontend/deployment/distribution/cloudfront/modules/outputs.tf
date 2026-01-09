output "hosting_bucket_name" {
  description = "S3 bucket name"
  value       = data.aws_s3_bucket.static.id
}

output "hosting_bucket_arn" {
  description = "S3 bucket ARN"
  value       = data.aws_s3_bucket.static.arn
}

output "hosting_s3_prefix" {
  description = "S3 prefix path for this scope"
  value       = var.hosting_s3_prefix
}

output "hosting_cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.static.id
}

output "hosting_cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = aws_cloudfront_distribution.static.domain_name
}

output "hosting_target_domain" {
  description = "Target domain for DNS records (CloudFront domain)"
  value       = local.hosting_target_domain
}

output "hosting_target_zone_id" {
  description = "Hosted zone ID for Route 53 alias records"
  value       = local.hosting_target_zone_id
}

output "hosting_record_type" {
  description = "DNS record type (A for CloudFront alias)"
  value       = local.hosting_record_type
}

output "hosting_website_url" {
  description = "Website URL"
  value       = var.hosting_custom_domain != null ? "https://${var.hosting_custom_domain}" : "https://${aws_cloudfront_distribution.static.domain_name}"
}
