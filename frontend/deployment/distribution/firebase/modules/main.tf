# Firebase Hosting
# Resources for Firebase static hosting

variable "hosting_project_id" {
  description = "GCP/Firebase project ID"
  type        = string
}

variable "hosting_app_name" {
  description = "Application name"
  type        = string
}

variable "hosting_environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "hosting_custom_domains" {
  description = "List of custom domains"
  type        = list(string)
  default     = []
}

variable "hosting_labels" {
  description = "Resource labels"
  type        = map(string)
  default     = {}
}

locals {
  hosting_site_id = "${var.hosting_app_name}-${var.hosting_environment}"

  hosting_default_labels = merge(var.hosting_labels, {
    application = replace(var.hosting_app_name, "-", "_")
    environment = var.hosting_environment
    managed_by  = "terraform"
  })
}

resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.hosting_project_id
}

resource "google_firebase_hosting_site" "default" {
  provider = google-beta
  project  = google_firebase_project.default.project
  site_id  = local.hosting_site_id
}

resource "google_firebase_hosting_custom_domain" "domains" {
  for_each = toset(var.hosting_custom_domains)

  provider      = google-beta
  project       = google_firebase_project.default.project
  site_id       = google_firebase_hosting_site.default.site_id
  custom_domain = each.value

  wait_dns_verification = false
}

output "hosting_project_id" {
  description = "Firebase project ID"
  value       = google_firebase_project.default.project
}

output "hosting_site_id" {
  description = "Firebase Hosting site ID"
  value       = google_firebase_hosting_site.default.site_id
}

output "hosting_default_url" {
  description = "Firebase Hosting default URL"
  value       = "https://${google_firebase_hosting_site.default.site_id}.web.app"
}

output "hosting_firebaseapp_url" {
  description = "Firebase alternative URL"
  value       = "https://${google_firebase_hosting_site.default.site_id}.firebaseapp.com"
}

output "hosting_website_url" {
  description = "Website URL"
  value       = length(var.hosting_custom_domains) > 0 ? "https://${var.hosting_custom_domains[0]}" : "https://${google_firebase_hosting_site.default.site_id}.web.app"
}
