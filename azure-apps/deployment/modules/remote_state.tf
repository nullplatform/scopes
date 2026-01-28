# =============================================================================
# REMOTE STATE - Read current state for blue-green deployments
# =============================================================================
# This data source reads the current Terraform state to get the existing
# production docker image. Used when preserve_production_image is enabled
# to keep the current production image while deploying a new image to staging.

data "terraform_remote_state" "current" {
  count   = var.preserve_production_image && var.backend_storage_account_name != "" ? 1 : 0
  backend = "azurerm"

  config = {
    storage_account_name = var.backend_storage_account_name
    container_name       = var.backend_container_name
    resource_group_name  = var.backend_resource_group_name
    key                  = var.state_key
    use_azuread_auth     = true
  }
}

locals {
  # Get the current production image from state, empty if no state exists yet
  current_production_image = (
    var.preserve_production_image && length(data.terraform_remote_state.current) > 0
    ? try(data.terraform_remote_state.current[0].outputs.docker_image, "")
    : ""
  )

  # Effective production image:
  # - If preserve mode is enabled AND state exists with an image: use the existing image
  # - Otherwise: use the new docker_image from variables
  effective_docker_image = (
    var.preserve_production_image && local.current_production_image != ""
    ? local.current_production_image
    : var.docker_image
  )
}
