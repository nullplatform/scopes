variable "azure_provider" {
  description = "Azure provider configuration"
  type = object({
    subscription_id = string
    resource_group  = string
    storage_account = string
    container       = string
  })
}

variable "provider_resource_tags_json" {
  description = "Resource tags as JSON object - applied as default tags to all Azure resources"
  type        = map(string)
  default     = {}
}
