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
      }
    }
  }
}
