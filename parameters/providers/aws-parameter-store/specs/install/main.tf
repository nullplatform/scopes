module "parameter_store" {
  source = "../../../shared/install"

  nrn                   = var.nrn
  np_api_key            = var.np_api_key
  extra_visible_to_nrns = var.extra_visible_to_nrns
  instances             = local.instances
  template_path         = "${path.module}/aws-parameter-store-configuration.json.tpl"
}

