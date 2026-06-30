output "specification_id" {
  description = "ID of the nullplatform_provider_specification created from aws-secrets-manager-configuration.json.tpl."
  value       = nullplatform_provider_specification.this.id
}
