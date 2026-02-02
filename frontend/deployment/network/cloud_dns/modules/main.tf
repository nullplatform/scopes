# GCP Cloud DNS Configuration
# Creates DNS records pointing to hosting resources (Load Balancer, Firebase, etc.)

variable "network_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "network_managed_zone" {
  description = "Cloud DNS managed zone name"
  type        = string
}

variable "network_domain" {
  description = "Domain name for the application"
  type        = string
}

variable "network_target_ip" {
  description = "Target IP address (for A records)"
  type        = string
  default     = null
}

variable "network_target_domain" {
  description = "Target domain (for CNAME records)"
  type        = string
  default     = null
}

variable "network_record_type" {
  description = "DNS record type (A or CNAME)"
  type        = string
  default     = "A"
}

variable "network_ttl" {
  description = "DNS record TTL in seconds"
  type        = number
  default     = 300
}

variable "network_create_www" {
  description = "Create www subdomain record as well"
  type        = bool
  default     = true
}

# A record
resource "google_dns_record_set" "main_a" {
  count = var.network_record_type == "A" && var.network_target_ip != null ? 1 : 0

  name         = "${var.network_domain}."
  project      = var.network_project_id
  type         = "A"
  ttl          = var.network_ttl
  managed_zone = var.network_managed_zone
  rrdatas      = [var.network_target_ip]
}

# CNAME record
resource "google_dns_record_set" "main_cname" {
  count = var.network_record_type == "CNAME" && var.network_target_domain != null ? 1 : 0

  name         = "${var.network_domain}."
  project      = var.network_project_id
  type         = "CNAME"
  ttl          = var.network_ttl
  managed_zone = var.network_managed_zone
  rrdatas      = ["${var.network_target_domain}."]
}

# WWW subdomain (A record)
resource "google_dns_record_set" "www_a" {
  count = var.network_create_www && var.network_record_type == "A" && var.network_target_ip != null ? 1 : 0

  name         = "www.${var.network_domain}."
  project      = var.network_project_id
  type         = "A"
  ttl          = var.network_ttl
  managed_zone = var.network_managed_zone
  rrdatas      = [var.network_target_ip]
}

# WWW subdomain (CNAME record)
resource "google_dns_record_set" "www_cname" {
  count = var.network_create_www && var.network_record_type == "CNAME" && var.network_target_domain != null ? 1 : 0

  name         = "www.${var.network_domain}."
  project      = var.network_project_id
  type         = "CNAME"
  ttl          = var.network_ttl
  managed_zone = var.network_managed_zone
  rrdatas      = ["${var.network_target_domain}."]
}

output "network_domain" {
  description = "Configured domain"
  value       = var.network_domain
}

output "network_website_url" {
  description = "Website URL"
  value       = "https://${var.network_domain}"
}
