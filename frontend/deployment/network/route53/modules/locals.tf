locals {
  # Expose network_domain for cross-module use (e.g., ACM certificate lookup)
  network_domain = var.network_domain

  # Compute full domain from domain + subdomain
  network_full_domain = var.network_subdomain != "" ? "${var.network_subdomain}.${var.network_domain}" : var.network_domain
}