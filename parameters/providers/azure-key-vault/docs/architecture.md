# Azure Key Vault — Provider Architecture

This document describes the `parameters/providers/azure-key-vault/` implementation. It stores nullplatform parameters as Azure Key Vault (AKV) secrets, exploiting AKV's native versioning.

---

## Lifecycle

| Step | What happens                                                                  |
|------|-------------------------------------------------------------------------------|
| `setup`     | Reads `AZ_VAULT_NAME`, `AZ_SECRET_PREFIX` (default `nullplatform-`). Validates prefix matches `[A-Za-z0-9-]*`. |
| `store`     | Composes canonical path via `build_external_id`. Transforms (slash → dash, equals → dash) for AKV naming. Calls `az keyvault secret set` with `--tags managed_by=nullplatform`. Extracts version from the returned id URL. Returns `external_id = <canonical_path>#<version>`. |
| `retrieve`  | Parses canonical path + version. Re-transforms path to AKV name. Calls `az keyvault secret show` with `--version <V>` if a version is present. |
| `delete`    | Calls `az keyvault secret delete` + best-effort `purge`. Idempotent. |
| `notify`    | Not implemented — dispatcher returns default `{success: true}`. |

---

## Storage layout

AKV secret names allow only alphanumerics and dashes (no slashes, no equals, no underscores). The canonical path from `build_external_id` contains slashes and equals, so we transform it:

```
canonical:  organization=acme-1255165411/account=prod-95118862/.../DB_PASSWORD-42
AKV name:   nullplatform-organization-acme-1255165411-account-prod-95118862-...-DB_PASSWORD-42
```

The transformation is `/=` → `-`, deterministic. The canonical form (with `/` and `=`) is what nullplatform sees in `external_id`; the AKV-safe form is only used internally to address the secret.

The canonical path follows the standard convention: required entities `organization`, `account`, `namespace`, `application`, plus the optional `scope` entity (when the parameter is bound to a deployment scope), plus optional dimensions (zero or more, sorted alphabetically). See `parameters/docs/architecture.md` for the complete naming convention.

Max secret name length in AKV is 127 characters. The provider checks this and surfaces a helpful error if exceeded.

---

## Versioning

AKV has native versioning. Every `az keyvault secret set` creates a new version, all retained inside the same secret. The version identifier is the last segment of the returned `id` URL.

### Version identity in external_id

The `external_id` returned by `store` encodes both the path and the version:

```
<canonical_path>#<version_id>
```

For Azure Key Vault, `version_id` is **the literal hex string version returned by AKV** — we do not invent or normalize it. AKV returns the secret's id as a URL like `https://my-vault.vault.azure.net/secrets/my-secret/93a0b2eb12a64fa7b3acb18900a8d33d`; we extract the last path segment. Real example:

```
organization=acme-1255165411/.../DB_PASSWORD-42#93a0b2eb12a64fa7b3acb18900a8d33d
```

That 32-char hex string is the AKV version identifier. It can be used as-is with `az keyvault secret show --version 93a0b2eb12a64fa7b3acb18900a8d33d` to fetch that specific historical version.

On `retrieve`:
- With `#<hex>` → fetch that version via `--version <hex>`.
- Without → fetch the latest.

On `delete`, the version suffix is ignored — `secret delete` + `secret purge` remove all versions.

---

## Soft-delete + purge

AKV uses soft-delete by default (90-day retention). The provider does both:

1. `az keyvault secret delete` — moves to soft-deleted state.
2. `az keyvault secret purge` — hard-deletes from the soft-delete bin, freeing the name immediately.

If the identity lacks `Purge` permission, purge fails with a warning but delete still succeeds. The secret stays in the soft-delete window and is auto-cleaned by Azure at retention expiry.

---

## Configuration

`PROVIDER_CONFIG` shape:

```json
{
  "vault_name":    "my-keyvault",
  "secret_prefix": "nullplatform-"
}
```

Authentication comes from the Azure CLI's default credential chain (managed identity, az login, service principal env vars).
