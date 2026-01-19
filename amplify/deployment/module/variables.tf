variable "aws_region" {
  description = "AWS Region"
  type = string
  default = "us-east-1"
}

variable "github_token" {
  description = "GitHub OAuth token for Amplify"
  type = string
  sensitive = true
}

variable "application_name" {
  description = "Application slug"
  type = string
}

variable "repository_url" {
  description = "GitHub repository url"
  type = string
}

variable "application_version" {
  description = "Application version to deploy"
  type = string
}

variable "env_vars_json" {
  description = "JSON object with environment variables"
  type = string
}

variable "resource_tags_json" {
  description = "JSON object with tags for AWS resources"
}

variable "domain" {
  description = "Root public domain (e.g. nullapps.io"
  type = string
}

variable "subdomain" {
  description = "Application subdomain domain (e.g. app)"
  type = string
}