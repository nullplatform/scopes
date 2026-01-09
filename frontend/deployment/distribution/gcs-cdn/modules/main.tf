# GCP Cloud Storage + Cloud CDN Hosting
# Resources for GCS static hosting with Cloud CDN

variable "hosting_project_id" {
  description = "GCP project ID"
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

variable "hosting_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "hosting_custom_domain" {
  description = "Custom domain (e.g., app.example.com)"
  type        = string
  default     = null
}

variable "hosting_labels" {
  description = "Resource labels"
  type        = map(string)
  default     = {}
}

locals {
  hosting_bucket_name = "${var.hosting_app_name}-${var.hosting_environment}-static-${var.hosting_project_id}"

  hosting_default_labels = merge(var.hosting_labels, {
    application = var.hosting_app_name
    environment = var.hosting_environment
    managed_by  = "terraform"
  })
}

resource "google_storage_bucket" "static" {
  name          = local.hosting_bucket_name
  project       = var.hosting_project_id
  location      = var.hosting_region
  force_destroy = false

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  versioning {
    enabled = true
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  uniform_bucket_level_access = true

  labels = local.hosting_default_labels
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.static.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_compute_backend_bucket" "static" {
  name        = "${var.hosting_app_name}-${var.hosting_environment}-backend"
  project     = var.hosting_project_id
  bucket_name = google_storage_bucket.static.name

  enable_cdn = true

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    client_ttl        = 3600
    default_ttl       = 3600
    max_ttl           = 86400
    negative_caching  = true
    serve_while_stale = 86400

    negative_caching_policy {
      code = 404
      ttl  = 60
    }
  }
}

resource "google_compute_url_map" "static" {
  name            = "${var.hosting_app_name}-${var.hosting_environment}-urlmap"
  project         = var.hosting_project_id
  default_service = google_compute_backend_bucket.static.id
}

resource "google_compute_managed_ssl_certificate" "static" {
  count   = var.hosting_custom_domain != null ? 1 : 0
  name    = "${var.hosting_app_name}-${var.hosting_environment}-cert"
  project = var.hosting_project_id

  managed {
    domains = [var.hosting_custom_domain]
  }
}

resource "google_compute_target_https_proxy" "static" {
  count            = var.hosting_custom_domain != null ? 1 : 0
  name             = "${var.hosting_app_name}-${var.hosting_environment}-https-proxy"
  project          = var.hosting_project_id
  url_map          = google_compute_url_map.static.id
  ssl_certificates = [google_compute_managed_ssl_certificate.static[0].id]
}

resource "google_compute_target_http_proxy" "static" {
  name    = "${var.hosting_app_name}-${var.hosting_environment}-http-proxy"
  project = var.hosting_project_id
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_url_map" "http_redirect" {
  name    = "${var.hosting_app_name}-${var.hosting_environment}-http-redirect"
  project = var.hosting_project_id

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_global_address" "static" {
  name    = "${var.hosting_app_name}-${var.hosting_environment}-ip"
  project = var.hosting_project_id
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.hosting_custom_domain != null ? 1 : 0
  name                  = "${var.hosting_app_name}-${var.hosting_environment}-https-rule"
  project               = var.hosting_project_id
  ip_address            = google_compute_global_address.static.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.static[0].id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.hosting_app_name}-${var.hosting_environment}-http-rule"
  project               = var.hosting_project_id
  ip_address            = google_compute_global_address.static.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.static.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

output "hosting_bucket_name" {
  description = "GCS bucket name"
  value       = google_storage_bucket.static.name
}

output "hosting_bucket_url" {
  description = "GCS bucket URL"
  value       = google_storage_bucket.static.url
}

output "hosting_load_balancer_ip" {
  description = "Load Balancer IP"
  value       = google_compute_global_address.static.address
}

output "hosting_website_url" {
  description = "Website URL"
  value       = var.hosting_custom_domain != null ? "https://${var.hosting_custom_domain}" : "http://${google_compute_global_address.static.address}"
}

output "hosting_upload_command" {
  description = "Command to upload files"
  value       = "gsutil -m rsync -r ./dist gs://${google_storage_bucket.static.name}"
}
