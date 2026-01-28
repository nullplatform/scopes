data "aws_s3_bucket" "static" {
  bucket = var.distribution_bucket_name
}

data "aws_caller_identity" "current" {}

# Look up ACM certificate for custom domain (must be in us-east-1 for CloudFront)
# Uses wildcard pattern: *.parent-domain.tld
# Note: PENDING_VALIDATION is included for LocalStack compatibility in integration tests
data "aws_acm_certificate" "custom_domain" {
  count = local.distribution_acm_certificate_domain != "" ? 1 : 0

  provider    = aws
  domain      = local.distribution_acm_certificate_domain
  statuses    = ["ISSUED", "PENDING_VALIDATION"]
  most_recent = true
}