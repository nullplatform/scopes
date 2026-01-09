variable "distribution_bucket_name" {
  description = "Existing S3 bucket name for static website distribution"
  type        = string
}

variable "distribution_s3_prefix" {
  description = "S3 prefix/path for this scope's files (e.g., 'app-name/scope-id')"
  type        = string
}

variable "distribution_app_name" {
  description = "Application name (used for resource naming)"
  type        = string
}

variable "distribution_custom_domain" {
  description = "Custom domain for CloudFront (optional)"
  type        = string
  default     = null
}

variable "distribution_resource_tags_json" {
  description = "Resource tags as JSON object"
  type        = map(string)
  default     = {}
}
