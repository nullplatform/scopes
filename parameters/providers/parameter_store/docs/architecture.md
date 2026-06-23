# AWS Systems Manager Parameter Store — Provider Architecture

This document describes the `parameters/providers/parameter_store/` implementation. It stores nullplatform parameters as AWS SSM Parameter Store entries, using `String` for plain parameters and `SecureString` (KMS-encrypted) for secrets.

This is the cheapest provider in the package — Standard tier is free up to 10,000 parameters.

---

## Lifecycle

| Step | What happens                                                                |
|------|-----------------------------------------------------------------------------|
| `setup`     | Reads `AWS_REGION`, `PS_NAME_PREFIX`, `PS_KMS_KEY_ID`, `PS_TIER`. Normalizes prefix to start/end with `/`. Fails if region is missing or tier is invalid. |
| `store`     | Generates a UUID. Calls `aws ssm put-parameter` with `Type=String` (kind=parameter) or `Type=SecureString` (kind=secret). Returns `{external_id, metadata}`. |
| `retrieve`  | Calls `aws ssm get-parameter --with-decryption`. Returns `{value}` or `{value: "value not found"}`. |
| `delete`    | Calls `aws ssm delete-parameter`. Idempotent — never errors. |
| `notify`    | Not implemented — dispatcher returns default `{success: true}`. |

---

## Type selection via PARAMETER_KIND

This is the first provider in the package that branches on `PARAMETER_KIND`:

| Kind        | SSM Type        | KMS                                                  |
|-------------|-----------------|------------------------------------------------------|
| `parameter` | `String`        | None (plain text)                                    |
| `secret`    | `SecureString`  | `PS_KMS_KEY_ID` if set, otherwise `alias/aws/ssm`    |

For `aws_secret_manager`, `hashicorp_vault`, and `azure_key_vault`, the kind is informational — those backends encrypt all values uniformly. Parameter Store is different because it distinguishes the storage type at the API level.

---

## Naming convention

```
<PS_NAME_PREFIX><external_id>
```

- `PS_NAME_PREFIX` defaults to `/nullplatform/parameters/`. Always starts with `/` (SSM hierarchical naming) and ends with `/` (the script normalizes both).
- `external_id` is a UUIDv4 generated at store time.
- Full parameter name example: `/nullplatform/parameters/f47ac10b-58cc-4372-a567-0e02b2c3d479`

The hierarchical prefix lets you scope IAM via path-based ARN patterns:
```
arn:aws:ssm:<region>:<account>:parameter/nullplatform/parameters/*
```

---

## Tiers

Parameter Store has three tiers, selected via `PS_TIER`:

| Tier                  | Free                  | Value size  | Use case                          |
|-----------------------|-----------------------|-------------|-----------------------------------|
| `Standard` (default)  | up to 10,000 params   | 4 KB        | Most cases                        |
| `Advanced`            | $0.05/param/month     | 8 KB        | Large values or > 10k params      |
| `Intelligent-Tiering` | Auto-promotes         | varies      | Mixed sizes, optimize for cost    |

Standard is the default and what most consumers should use. Switch to Advanced explicitly when you have a value > 4 KB or you'll cross 10,000 parameters.

---

## Cost model

```
Standard:           $0.00 / param / month  (up to 10,000)
                    $0.05 / 10,000 API calls
Advanced:           $0.05 / param / month
                    $0.05 / 10,000 API calls
Intelligent-Tiering: varies (sees Advanced rate once promoted)
```

For 100 secret parameters across all your apps on Standard tier: **$0/month** (vs ~$40/month with Secrets Manager). The trade-off: Parameter Store has no rotation, no replication, no resource-based policies — features Secrets Manager provides for the extra cost.

---

## Configuration

`PROVIDER_CONFIG` shape:

```json
{
  "region":      "us-east-1",
  "name_prefix": "/nullplatform/parameters/",
  "kms_key_id":  "alias/parameters-secure",
  "tier":        "Standard"
}
```

Equivalent env vars: `AWS_REGION`, `PS_NAME_PREFIX`, `PS_KMS_KEY_ID`, `PS_TIER`. `PROVIDER_CONFIG` wins per `get_config_value` priority.

`kms_key_id` is only used when storing a `SecureString` (kind=secret). For plain parameters it's ignored.

---

## Compatibility with the contract

| Operation | Output shape | Notes |
|-----------|--------------|-------|
| store     | `{external_id, metadata: {parameter_name, region, type, tier}}` | `type` reflects the SSM Type used (String or SecureString) |
| retrieve  | `{value}` or `{value: "value not found"}` | --with-decryption is always passed; no-op for String |
| delete    | `{success: true}` | Always; idempotent |
