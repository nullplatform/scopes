# HashiCorp Vault — Provider Architecture

This document describes the `parameters/providers/hashicorp-vault/` implementation. It stores nullplatform parameters as Vault KV v2 secrets, exploiting Vault's native versioning.

---

## Lifecycle

| Step | What happens                                                                          |
|------|---------------------------------------------------------------------------------------|
| `setup`     | Reads `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_PATH_PREFIX` (default `secret/data/nullplatform`). Fails fast if address or token is missing. |
| `store`     | Composes the canonical path via `build_external_id`. POSTs to `$VAULT_ADDR/v1/$VAULT_PATH_PREFIX/<path>` with a JSON payload. Captures the new version number from Vault's response. Returns `external_id = <path>#<version>`. |
| `retrieve`  | Parses `EXTERNAL_ID` into path + version. GETs `$VAULT_ADDR/v1/$VAULT_PATH_PREFIX/<path>?version=<N>` if a version is present; otherwise fetches the latest. Returns `{value}` or `{value: "value not found"}`. |
| `delete`    | Parses path from external_id. DELETEs the metadata endpoint (KV v2) — removes all versions. Idempotent. |
| `notify`    | Not implemented — dispatcher returns default `{success: true}`. |

---

## Storage layout

Every secret path is composed by `parameters/utils/build_external_id`:

```
<VAULT_PATH_PREFIX>/organization=<slug>-<id>/account=<slug>-<id>/namespace=<slug>-<id>/application=<slug>-<id>[/scope=<slug>-<id>][/<dim_key>=<dim_value>...]/<parameter_name>-<parameter_id>
```

The `scope` entity is optional (only present when the parameter is bound to a deployment scope). Dimensions are also optional — a parameter may have zero of them. See `parameters/docs/architecture.md` for the complete naming convention.

Default `VAULT_PATH_PREFIX` is `secret/data/nullplatform` (KV v2 — note the `data/` segment is required by the v2 API).

Example full path:

```
secret/data/nullplatform/organization=acme-1255165411/account=prod-95118862/.../DB_PASSWORD-42
```

The path is human-friendly: navigating the Vault UI, an operator can find any secret by knowing the parameter's NRN + dimensions + name.

---

## Versioning

Vault KV v2 has native versioning. Every `POST /v1/secret/data/<path>` creates a new version, all retained inside the same path. Old versions can be fetched with `?version=<N>`.

### Version identity in external_id

The `external_id` returned by `store` encodes both the path and the version:

```
<canonical_path>#<version_id>
```

For Vault KV v2, `version_id` is **the literal integer version number returned by Vault** in `.data.version` — we do not invent or normalize it. Real example:

```
organization=acme-1255165411/.../DB_PASSWORD-42#3
```

Here `3` means "Vault version 3 of this secret". It can be used as-is with `?version=3` to fetch that specific version.

On `retrieve`:
- If `external_id` carries `#<N>` → fetch that historical version via `?version=N`.
- If no `#` suffix → fetch the latest (default Vault behavior).

On `delete`, the version suffix is ignored. KV v2's data DELETE removes the latest version label; for full purging across all versions you'd use `metadata` endpoint — see Vault docs for the soft/hard delete distinction.

---

## Secret payload

The body stored in Vault is a JSON envelope:

```json
{
  "data": {
    "parameter_id": 42,
    "value": "the-actual-value",
    "stored_at": "2026-06-23T12:34:56Z",
    "external_id": "organization=acme-1255165411/.../DB_PASSWORD-42"
  }
}
```

The `data` wrapper is KV v2's API requirement; the inner object is our envelope.

---

## Authentication

Token-based via `X-Vault-Token` header. The token must have read/write permissions on the configured `VAULT_PATH_PREFIX` namespace.

For production: use short-lived tokens (issued by AppRole, Kubernetes auth, etc.) refreshed by the operator outside this package. The agent only reads `VAULT_TOKEN` — credential lifecycle management is the operator's responsibility.
