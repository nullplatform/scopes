# AWS Amplify Hosting
# Resources for AWS Amplify static frontend hosting

variable "hosting_app_name" {
  description = "Application name"
  type        = string
}

variable "hosting_environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "hosting_repository_url" {
  description = "Git repository URL"
  type        = string
}

variable "hosting_branch_name" {
  description = "Branch to deploy"
  type        = string
  default     = "main"
}

variable "hosting_github_access_token" {
  description = "GitHub access token"
  type        = string
  sensitive   = true
  default     = null
}

variable "hosting_custom_domain" {
  description = "Custom domain (e.g., app.example.com)"
  type        = string
  default     = null
}

variable "hosting_environment_variables" {
  description = "Environment variables for the application"
  type        = map(string)
  default     = {}
}

variable "hosting_build_spec" {
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

variable "hosting_framework" {
  description = "Application framework (React, Vue, Angular, etc.)"
  type        = string
  default     = "React"
}

variable "hosting_resource_tags_json" {
  description = "Resource tags as JSON object"
  type        = map(string)
  default     = {}
}

locals {
  hosting_default_tags = merge(var.hosting_resource_tags_json, {
    Application = var.hosting_app_name
    Environment = var.hosting_environment
    ManagedBy   = "terraform"
    Module      = "hosting/amplify"
  })

  hosting_env_vars = merge({
    ENVIRONMENT = var.hosting_environment
    APP_NAME    = var.hosting_app_name
  }, var.hosting_environment_variables)
}

resource "aws_amplify_app" "main" {
  name       = "${var.hosting_app_name}-${var.hosting_environment}"
  repository = var.hosting_repository_url

  access_token = var.hosting_github_access_token
  build_spec   = var.hosting_build_spec
  environment_variables = local.hosting_env_vars

  custom_rule {
    source = "</^[^.]+$|\\.(?!(css|gif|ico|jpg|js|png|txt|svg|woff|woff2|ttf|map|json)$)([^.]+$)/>"
    status = "200"
    target = "/index.html"
  }

  enable_auto_branch_creation = false
  enable_branch_auto_build    = true
  enable_branch_auto_deletion = false
  platform = "WEB"

  tags = local.hosting_default_tags
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.hosting_branch_name

  framework = var.hosting_framework
  stage     = var.hosting_environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"
  enable_auto_build = true

  environment_variables = {
    BRANCH = var.hosting_branch_name
  }

  tags = local.hosting_default_tags
}

resource "aws_amplify_domain_association" "main" {
  count = var.hosting_custom_domain != null ? 1 : 0

  app_id      = aws_amplify_app.main.id
  domain_name = var.hosting_custom_domain

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
  hosting_target_domain = "${aws_amplify_branch.main.branch_name}.${aws_amplify_app.main.id}.amplifyapp.com"
  # Amplify uses CNAME records, not alias - so no hosted zone ID needed
  hosting_target_zone_id = null
  # Amplify requires CNAME records
  hosting_record_type = "CNAME"
}

output "hosting_app_id" {
  description = "Amplify application ID"
  value       = aws_amplify_app.main.id
}

output "hosting_app_arn" {
  description = "Amplify application ARN"
  value       = aws_amplify_app.main.arn
}

output "hosting_default_domain" {
  description = "Amplify default domain"
  value       = "https://${local.hosting_target_domain}"
}

output "hosting_target_domain" {
  description = "Target domain for DNS records"
  value       = local.hosting_target_domain
}

output "hosting_target_zone_id" {
  description = "Hosted zone ID for alias records (null for Amplify/CNAME)"
  value       = local.hosting_target_zone_id
}

output "hosting_record_type" {
  description = "DNS record type to use (CNAME for Amplify)"
  value       = local.hosting_record_type
}

output "hosting_website_url" {
  description = "Website URL"
  value       = var.hosting_custom_domain != null ? "https://${var.hosting_custom_domain}" : "https://${local.hosting_target_domain}"
}

output "hosting_webhook_url" {
  description = "Webhook URL for manual triggers"
  value       = aws_amplify_webhook.main.url
  sensitive   = true
}
