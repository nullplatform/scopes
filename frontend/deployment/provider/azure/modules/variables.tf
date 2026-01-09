variable "azure_provider" {
  description = "Azure provider configuration"
  type = object({
    subscription_id      = string
    resource_group_name  = string
    storage_account_name = string
    container_name       = string
  })
}