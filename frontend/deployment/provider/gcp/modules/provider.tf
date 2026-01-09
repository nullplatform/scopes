terraform {
  required_version = ">= 1.4.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.gcp_provider.project
  region  = var.gcp_provider.region
}

provider "google-beta" {
  project = var.gcp_provider.project
  region  = var.gcp_provider.region
}
