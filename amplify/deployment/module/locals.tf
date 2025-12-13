locals {
  git_ref = var.application_version
  env_vars = jsondecode(var.env_vars_json)
  resource_tags = jsondecode(var.resource_tags_json)
}