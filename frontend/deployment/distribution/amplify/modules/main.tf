# AWS Amplify Hosting
# Resources for AWS Amplify static frontend hosting

variable "distribution_app_name" {
  description = "Application name"
  type        = string
}

variable "distribution_environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "distribution_repository_url" {
  description = "Git repository URL"
  type        = string
}

variable "distribution_branch_name" {
  description = "Branch to deploy"
  type        = string
  default     = "main"
}

variable "distribution_github_access_token" {
  description = "GitHub access token"
  type        = string
  sensitive   = true
  default     = null
}

variable "distribution_custom_domain" {
  description = "Custom domain (e.g., app.example.com)"
  type        = string
  default     = null
}

variable "distribution_environment_variables" {
  description = "Environment variables for the application"
  type        = map(string)
  default     = {}
}

variable "distribution_build_spec" {
  description = "Build specification in YAML format"
  type        = string
  default     = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: dist
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT
}

variable "distribution_framework" {
  description = "Application framework (React, Vue, Angular, etc.)"
  type        = string
  default     = "React"
}

variable "distribution_resource_tags_json" {
  description = "Resource tags as JSON object"
  type        = map(string)
  default     = {}
}

locals {
  distribution_default_tags = merge(var.distribution_resource_tags_json, {
    Application = var.distribution_app_name
    Environment = var.distribution_environment
    ManagedBy   = "terraform"
    Module      = "hosting/amplify"
  })

  distribution_env_vars = merge({
    ENVIRONMENT = var.distribution_environment
    APP_NAME    = var.distribution_app_name
  }, var.distribution_environment_variables)
}

resource "aws_amplify_app" "main" {
  name       = "${var.distribution_app_name}-${var.distribution_environment}"
  repository = var.distribution_repository_url

  access_token = var.distribution_github_access_token
  build_spec   = var.distribution_build_spec
  environment_variables = local.distribution_env_vars

  custom_rule {
    source = "</^[^.]+$|\\.(?!(css|gif|ico|jpg|js|png|txt|svg|woff|woff2|ttf|map|json)$)([^.]+$)/>"
    status = "200"
    target = "/index.html"
  }

  enable_auto_branch_creation = false
  enable_branch_auto_build    = true
  enable_branch_auto_deletion = false
  platform = "WEB"

  tags = local.distribution_default_tags
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.distribution_branch_name

  framework = var.distribution_framework
  stage     = var.distribution_environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"
  enable_auto_build = true

  environment_variables = {
    BRANCH = var.distribution_branch_name
  }

  tags = local.distribution_default_tags
}

resource "aws_amplify_domain_association" "main" {
  count = var.distribution_custom_domain != null ? 1 : 0

  app_id      = aws_amplify_app.main.id
  domain_name = var.distribution_custom_domain

  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = ""
  }

  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = "www"
  }

  wait_for_verification = false
}

resource "aws_amplify_webhook" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = aws_amplify_branch.main.branch_name
  description = "Webhook for manual build triggers"
}

# Locals for cross-module references (consumed by network/route53)
locals {
  # Amplify default domain for DNS pointing
  distribution_target_domain = "${aws_amplify_branch.main.branch_name}.${aws_amplify_app.main.id}.amplifyapp.com"
  # Amplify uses CNAME records, not alias - so no hosted zone ID needed
  distribution_target_zone_id = null
  # Amplify requires CNAME records
  distribution_record_type = "CNAME"
}

output "distribution_app_id" {
  description = "Amplify application ID"
  value       = aws_amplify_app.main.id
}

output "distribution_app_arn" {
  description = "Amplify application ARN"
  value       = aws_amplify_app.main.arn
}

output "distribution_default_domain" {
  description = "Amplify default domain"
  value       = "https://${local.distribution_target_domain}"
}

output "distribution_target_domain" {
  description = "Target domain for DNS records"
  value       = local.distribution_target_domain
}

output "distribution_target_zone_id" {
  description = "Hosted zone ID for alias records (null for Amplify/CNAME)"
  value       = local.distribution_target_zone_id
}

output "distribution_record_type" {
  description = "DNS record type to use (CNAME for Amplify)"
  value       = local.distribution_record_type
}

output "distribution_website_url" {
  description = "Website URL"
  value       = var.distribution_custom_domain != null ? "https://${var.distribution_custom_domain}" : "https://${local.distribution_target_domain}"
}

output "distribution_webhook_url" {
  description = "Webhook URL for manual triggers"
  value       = aws_amplify_webhook.main.url
  sensitive   = true
}
