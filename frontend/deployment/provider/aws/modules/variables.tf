variable "aws_provider" {
  description = "AWS provider configuration"
  type = object({
    region       = string
    state_bucket = string
    lock_table   = string
  })
}

variable "provider_resource_tags_json" {
  description = "Resource tags as JSON object - applied as default tags to all AWS resources"
  type        = map(string)
  default     = {}
}