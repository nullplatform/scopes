{
  "name": "HashiCorp Vault",
  "description": "Stores nullplatform parameter values in HashiCorp Vault KV v2 with native versioning",
  "slug": "hashicorp-vault",
  "category": "parameters-storage",
  "icon": "mdi:vault",
  "visible_to": [
    "{{ env.Getenv \"NRN\" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "required": ["sensibility", "setup"],
    "additionalProperties": false,
    "properties": {
      "sensibility": {
        "type": "object",
        "order": 1,
        "required": ["applies_to"],
        "description": "The sensibility of the parameters stored in this backend.",
        "properties": {
          "applies_to": {
            "type": "array",
            "title": "Applies to",
            "description": "Which parameters this backend stores — secret, non-secret, or both.",
            "order": 1,
            "inline": true,
            "uniqueItems": true,
            "minItems": 1,
            "default": ["secret", "non_secret"],
            "items": {
              "oneOf": [
                { "const": "secret",     "title": "Secret parameters" },
                { "const": "non_secret", "title": "Non-secret parameters" }
              ]
            }
          }
        }
      },
      "setup": {
        "type": "object",
        "order": 2,
        "required": ["address"],
        "description": "The setup for the HashiCorp Vault backend.",
        "properties": {
          "address": {
            "type": "string",
            "title": "Vault Address",
            "description": "Vault HTTP(S) endpoint (e.g. https://vault.example.com:8200)",
            "order": 1
          }
        }
      }
    }
  }
}
