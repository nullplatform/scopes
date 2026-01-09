locals {
  # Compute full domain from domain + subdomain
  network_full_domain = var.network_subdomain != "" ? "${var.network_subdomain}.${var.network_domain}" : var.network_domain
}