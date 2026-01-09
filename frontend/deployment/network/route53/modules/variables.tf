variable "network_hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "network_domain" {
  description = "Root domain name (e.g., example.com)"
  type        = string
}

variable "network_subdomain" {
  description = "Subdomain prefix (e.g., 'app' for app.example.com, empty string for apex)"
  type        = string
  default     = ""
}