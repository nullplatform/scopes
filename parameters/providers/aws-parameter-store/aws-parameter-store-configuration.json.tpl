{
  "name": "AWS Parameter Store",
  "description": "Stores nullplatform parameter values in AWS SSM Parameter Store with native versioning. Cheapest option (Standard tier is free up to 10,000 parameters)",
  "slug": "aws-parameter-store",
  "category": "parameters-storage",
  "icon": "mdi:aws",
  "visible_to": [
    "{{ env.Getenv \"NRN\" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "properties": {
      "kms_key_id": {
        "type": "string",
        "title": "KMS Key ID (optional)",
        "description": "Customer-managed KMS key for SecureString parameters. If empty, the default alias/aws/ssm key is used",
        "default": ""
      },
      "tier": {
        "type": "string",
        "title": "Parameter Tier",
        "description": "Standard is free for up to 10,000 parameters. Advanced supports larger values but costs $0.05/param/month",
        "default": "Standard",
        "oneOf": [
          { "const": "Standard", "title": "Standard (free)" },
          { "const": "Advanced", "title": "Advanced ($0.05/param/month)" },
          { "const": "Intelligent-Tiering", "title": "Intelligent-Tiering" }
        ]
      }
    }
  }
}
