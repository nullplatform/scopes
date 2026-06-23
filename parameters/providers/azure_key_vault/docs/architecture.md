# Azure Key Vault — Provider Architecture

This document describes the `parameters/providers/azure_key_vault/` implementation. It stores nullplatform parameters as Azure Key Vault (AKV) secrets.

---

## Lifecycle

| Step | What happens                                                                  |
|------|-------------------------------------------------------------------------------|
| `setup`     | Reads `AZ_VAULT_NAME`, `AZ_SECRET_PREFIX`. Fails if vault name missing or prefix has invalid chars. |
| `store`     | Generates UUID. Calls `az keyvault secret set`. Returns `{external_id, metadata}`. |
| `retrieve`  | Calls `az keyvault secret show`. Returns `{value}` or `{value: "value not found"}`. |
| `delete`    | Calls `az keyvault secret delete` + `az keyvault secret purge` (both with `\|\| true`). |
| `notify`    | Not implemented — dispatcher returns default `{success: true}`. |

---

## Naming convention

```
<AZ_SECRET_PREFIX><external_id>
```

- `AZ_SECRET_PREFIX` defaults to `parameters-`. Must match `[A-Za-z0-9-]*` — AKV secret names allow only alphanumerics and dashes (no slashes, no dots, no underscores).
- `external_id` is a UUIDv4 generated at store time. UUIDs already satisfy AKV's character constraints.
- Full secret name example: `parameters-f47ac10b-58cc-4372-a567-0e02b2c3d479`
- Max 127 chars total. With a UUID (36 chars + dashes), you have ~90 chars left for the prefix.

This naming differs from `aws_secret_manager` and `parameter_store` (which support slashes for hierarchical organization) — AKV is flat-namespace.

---

## PARAMETER_KIND is informational here

AKV transparently encrypts all secrets using vault-managed keys (or a customer key if the vault is configured with one). The provider does **not** branch on `PARAMETER_KIND`:

- `kind=secret` → AKV secret (encrypted at rest by AKV)
- `kind=parameter` → AKV secret (encrypted at rest by AKV)

Both end up identical. If you need to distinguish parameter vs secret semantics at the storage layer, use the `parameter_store` provider instead (it uses SSM Type=String vs SecureString).

---

## Soft-delete behavior

Azure Key Vault has soft-delete enabled by default with 90-day retention:

1. `az keyvault secret delete` moves the secret to a soft-deleted state. The name is reserved (cannot recreate with same name) and the secret is recoverable for 90 days.
2. `az keyvault secret purge` hard-deletes from the soft-delete bin, freeing the name immediately.

The provider's `delete` script does **both** sequentially. Both calls suppress errors (`|| true`), so:

- If you have the `Purge` permission: hard-deletes immediately, no retention cost.
- If you only have `Delete`: soft-deletes, retention applies. Since we use UUIDs, name reuse is not a concern in practice.
- If the secret already doesn't exist: both calls fail silently, the operation still returns `{success: true}`.

---

## Configuration

`PROVIDER_CONFIG` shape:

```json
{
  "vault_name":    "my-keyvault",
  "secret_prefix": "parameters-"
}
```

Equivalent env vars: `AZURE_KEY_VAULT_NAME`, `AZURE_KEY_VAULT_SECRET_PREFIX`. `PROVIDER_CONFIG` wins per `get_config_value` priority.

Authentication uses the Azure CLI's default credential chain:

1. Managed Identity (Azure-hosted environments)
2. Service Principal env vars (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`)
3. `az login` cached credentials

The provider does not validate auth in `setup` — the first `az keyvault` call surfaces auth errors.

---

## Required permissions on the vault

The identity running the provider scripts needs an access policy or RBAC role on the vault:

| Operation | Access policy permission       | RBAC role                            |
|-----------|--------------------------------|--------------------------------------|
| store     | Set                            | Key Vault Secrets Officer / Contributor |
| retrieve  | Get                            | Key Vault Secrets User               |
| delete    | Delete, Purge (optional)       | Key Vault Secrets Officer + Purge action |

The `Purge` permission is optional but recommended. Without it, soft-deletes accumulate and you may hit vault soft-delete quotas if you cycle many secrets.

---

## Compatibility with the contract

| Operation | Output shape | Notes |
|-----------|--------------|-------|
| store     | `{external_id, metadata: {azure_secret_id, secret_name, vault_name}}` | `azure_secret_id` is the full AKV resource ID (URL form) |
| retrieve  | `{value}` or `{value: "value not found"}` | |
| delete    | `{success: true}` | Always; idempotent |
