# Firebase Hosting
# Resources for Firebase static hosting

variable "distribution_project_id" {
  description = "GCP/Firebase project ID"
  type        = string
}

variable "distribution_app_name" {
  description = "Application name"
  type        = string
}

variable "distribution_environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "distribution_custom_domains" {
  description = "List of custom domains"
  type        = list(string)
  default     = []
}

variable "distribution_labels" {
  description = "Resource labels"
  type        = map(string)
  default     = {}
}

locals {
  distribution_site_id = "${var.distribution_app_name}-${var.distribution_environment}"

  distribution_default_labels = merge(var.distribution_labels, {
    application = replace(var.distribution_app_name, "-", "_")
    environment = var.distribution_environment
    managed_by  = "terraform"
  })
}

resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.distribution_project_id
}

resource "google_firebase_distribution_site" "default" {
  provider = google-beta
  project  = google_firebase_project.default.project
  site_id  = local.distribution_site_id
}

resource "google_firebase_distribution_custom_domain" "domains" {
  for_each = toset(var.distribution_custom_domains)

  provider      = google-beta
  project       = google_firebase_project.default.project
  site_id       = google_firebase_distribution_site.default.site_id
  custom_domain = each.value

  wait_dns_verification = false
}

output "distribution_project_id" {
  description = "Firebase project ID"
  value       = google_firebase_project.default.project
}

output "distribution_site_id" {
  description = "Firebase Hosting site ID"
  value       = google_firebase_distribution_site.default.site_id
}

output "distribution_default_url" {
  description = "Firebase Hosting default URL"
  value       = "https://${google_firebase_distribution_site.default.site_id}.web.app"
}

output "distribution_firebaseapp_url" {
  description = "Firebase alternative URL"
  value       = "https://${google_firebase_distribution_site.default.site_id}.firebaseapp.com"
}

output "distribution_website_url" {
  description = "Website URL"
  value       = length(var.distribution_custom_domains) > 0 ? "https://${var.distribution_custom_domains[0]}" : "https://${google_firebase_distribution_site.default.site_id}.web.app"
}
