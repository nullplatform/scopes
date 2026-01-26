variable "distribution_storage_account" {
  description = "Azure Storage account name for static website distribution"
  type        = string
}

variable "distribution_container_name" {
  description = "Azure Storage container name (defaults to $web for static websites)"
  type        = string
  default     = "$web"
}

variable "distribution_blob_prefix" {
  description = "Blob path prefix for this scope's files (e.g., '/app-name/scope-id')"
  type        = string
  default     = "/"
}

variable "distribution_app_name" {
  description = "Application name (used for resource naming)"
  type        = string
}

variable "distribution_resource_tags_json" {
  description = "Resource tags as JSON object"
  type        = map(string)
  default     = {}
}