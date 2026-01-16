variable "gcp_provider" {
  description = "GCP provider configuration"
  type = object({
    project = string
    region  = string
    bucket  = string
  })
}
