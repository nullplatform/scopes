{
  "name": "AWS Secrets Manager",
  "description": "Stores nullplatform parameter values in AWS Secrets Manager using native versioning",
  "slug": "aws-secrets-manager",
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
        "description": "Customer-managed KMS key ARN or alias. If empty, the default aws/secretsmanager managed key is used",
        "default": ""
      }
    }
  }
}
