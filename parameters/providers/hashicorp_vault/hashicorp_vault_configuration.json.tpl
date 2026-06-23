{
  "name": "HashiCorp Vault",
  "description": "Stores nullplatform parameter values in HashiCorp Vault KV v2 with native versioning",
  "slug": "hashicorp_vault",
  "category": "parameters-storage",
  "icon": "mdi:vault",
  "visible_to": [
    "{{ env.Getenv \"NRN\" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "required": [
      "address"
    ],
    "properties": {
      "address": {
        "type": "string",
        "title": "Vault Address",
        "description": "Vault HTTP(S) endpoint (e.g. https://vault.example.com:8200)"
      },
      "path_prefix": {
        "type": "string",
        "title": "Path Prefix",
        "description": "KV v2 path prefix prepended to every secret. Format: secret/data/<prefix>",
        "default": "secret/data/nullplatform"
      }
    }
  }
}
