# GCP Cloud Storage + Cloud CDN Hosting
# Resources for GCS static hosting with Cloud CDN

variable "distribution_project_id" {
  description = "GCP project ID"
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

variable "distribution_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "distribution_custom_domain" {
  description = "Custom domain (e.g., app.example.com)"
  type        = string
  default     = null
}

variable "distribution_labels" {
  description = "Resource labels"
  type        = map(string)
  default     = {}
}

locals {
  distribution_bucket_name = "${var.distribution_app_name}-${var.distribution_environment}-static-${var.distribution_project_id}"

  distribution_default_labels = merge(var.distribution_labels, {
    application = var.distribution_app_name
    environment = var.distribution_environment
    managed_by  = "terraform"
  })
}

resource "google_storage_bucket" "static" {
  name          = local.distribution_bucket_name
  project       = var.distribution_project_id
  location      = var.distribution_region
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

  labels = local.distribution_default_labels
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.static.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_compute_backend_bucket" "static" {
  name        = "${var.distribution_app_name}-${var.distribution_environment}-backend"
  project     = var.distribution_project_id
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
  name            = "${var.distribution_app_name}-${var.distribution_environment}-urlmap"
  project         = var.distribution_project_id
  default_service = google_compute_backend_bucket.static.id
}

resource "google_compute_managed_ssl_certificate" "static" {
  count   = var.distribution_custom_domain != null ? 1 : 0
  name    = "${var.distribution_app_name}-${var.distribution_environment}-cert"
  project = var.distribution_project_id

  managed {
    domains = [var.distribution_custom_domain]
  }
}

resource "google_compute_target_https_proxy" "static" {
  count            = var.distribution_custom_domain != null ? 1 : 0
  name             = "${var.distribution_app_name}-${var.distribution_environment}-https-proxy"
  project          = var.distribution_project_id
  url_map          = google_compute_url_map.static.id
  ssl_certificates = [google_compute_managed_ssl_certificate.static[0].id]
}

resource "google_compute_target_http_proxy" "static" {
  name    = "${var.distribution_app_name}-${var.distribution_environment}-http-proxy"
  project = var.distribution_project_id
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_url_map" "http_redirect" {
  name    = "${var.distribution_app_name}-${var.distribution_environment}-http-redirect"
  project = var.distribution_project_id

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_global_address" "static" {
  name    = "${var.distribution_app_name}-${var.distribution_environment}-ip"
  project = var.distribution_project_id
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.distribution_custom_domain != null ? 1 : 0
  name                  = "${var.distribution_app_name}-${var.distribution_environment}-https-rule"
  project               = var.distribution_project_id
  ip_address            = google_compute_global_address.static.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.static[0].id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.distribution_app_name}-${var.distribution_environment}-http-rule"
  project               = var.distribution_project_id
  ip_address            = google_compute_global_address.static.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.static.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

output "distribution_bucket_name" {
  description = "GCS bucket name"
  value       = google_storage_bucket.static.name
}

output "distribution_bucket_url" {
  description = "GCS bucket URL"
  value       = google_storage_bucket.static.url
}

output "distribution_load_balancer_ip" {
  description = "Load Balancer IP"
  value       = google_compute_global_address.static.address
}

output "distribution_website_url" {
  description = "Website URL"
  value       = var.distribution_custom_domain != null ? "https://${var.distribution_custom_domain}" : "http://${google_compute_global_address.static.address}"
}

output "distribution_upload_command" {
  description = "Command to upload files"
  value       = "gsutil -m rsync -r ./dist gs://${google_storage_bucket.static.name}"
}
