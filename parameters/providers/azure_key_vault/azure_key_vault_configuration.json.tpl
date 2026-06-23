{
  "name": "Azure Key Vault",
  "description": "Stores nullplatform parameter values in Azure Key Vault with native versioning",
  "slug": "azure_key_vault",
  "category": "parameters-storage",
  "icon": "mdi:microsoft-azure",
  "visible_to": [
    "{{ env.Getenv \"NRN\" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "required": [
      "vault_name"
    ],
    "properties": {
      "vault_name": {
        "type": "string",
        "title": "Vault Name",
        "description": "Azure Key Vault name (without https:// or .vault.azure.net suffix)"
      },
      "secret_prefix": {
        "type": "string",
        "title": "Secret Name Prefix",
        "description": "Prefix prepended to every secret name. AKV only allows alphanumerics and dashes",
        "default": "nullplatform-",
        "pattern": "^[A-Za-z0-9-]*$"
      }
    }
  }
}
