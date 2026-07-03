locals {
  template_raw      = file(var.template_path)
  template_rendered = replace(local.template_raw, "{{ env.Getenv \"NRN\" }}", var.nrn)
  config            = jsondecode(local.template_rendered)
  cmdline_path      = "nullplatform/scopes/parameters/entrypoint"

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