locals {
  # The configuration template uses gomplate-style `{{ env.Getenv "NRN" }}` for
  # `visible_to` because it's also consumed by non-tofu install paths. The only
  # token in the file is NRN, so we replace it inline rather than pulling in
  # gomplate as a build dependency.
  template_path     = "${path.module}/hashicorp-vault-configuration.json.tpl"
  template_raw      = file(local.template_path)
  template_rendered = replace(local.template_raw, "{{ env.Getenv \"NRN\" }}", var.nrn)
  config            = jsondecode(local.template_rendered)
  cmdline_path      = "nullplatform/scopes/parameters/entrypoint"

  # The spec must be visible to the anchor NRN and to every NRN where an
  # instance lives — otherwise the instance can't reference its own spec.
  instance_nrns = distinct([for _, inst in var.instances : inst.nrn])
  spec_visible_to = distinct(concat(
    [var.nrn],
    local.instance_nrns,
    var.extra_visible_to_nrns,
  ))

  # Instances that get their own agent API key + notification channel.
  notification_instances = {
    for key, instance in var.instances : key => instance
    if instance.notification_channel_enabled
  }

  api_key_grants = [
    "controlplane:agent",
    "developer",
    "ops",
    "secops",
    "secrets-reader",
  ]
}
