{
  "name": "AWS Secrets Manager",
  "description": "Stores nullplatform parameter values in AWS Secrets Manager using native versioning",
  "slug": "aws_secret_manager",
  "category": "parameters-storage",
  "icon": "mdi:aws",
  "visible_to": [
    "{{ env.Getenv \"NRN\" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "required": [
      "region"
    ],
    "properties": {
      "region": {
        "type": "string",
        "title": "AWS Region",
        "description": "AWS region where secrets will be stored (e.g. us-east-1)"
      },
      "name_prefix": {
        "type": "string",
        "title": "Secret Name Prefix",
        "description": "Prefix prepended to every secret name. Acts as the IAM scoping anchor",
        "default": "nullplatform/"
      },
      "kms_key_id": {
        "type": "string",
        "title": "KMS Key ID (optional)",
        "description": "Customer-managed KMS key ARN or alias. If empty, the default aws/secretsmanager managed key is used"
      }
    }
  }
}
