# HashiCorp Vault — Provider Architecture

This document describes the `parameters/providers/hashicorp_vault/` implementation. It stores nullplatform parameters as Vault KV v2 secrets.

---

## Lifecycle

| Step | What happens                                                          |
|------|-----------------------------------------------------------------------|
| `setup`     | Reads `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_PATH_PREFIX` from env or `PROVIDER_CONFIG`. Fails fast if address or token is missing. Exports the three vars. |
| `store`     | Generates a UUID `external_id`. POSTs to `$VAULT_ADDR/v1/$VAULT_PATH_PREFIX/$external_id` with a JSON payload. Returns `{external_id, metadata.vault_path}`. |
| `retrieve`  | GETs from `$VAULT_ADDR/v1/$VAULT_PATH_PREFIX/$external_id`. Returns `{value}` or `{value: "value not found"}` on miss. |
| `delete`    | DELETEs the secret. Idempotent — re-deleting is a no-op. Returns `{success: true}`. |
| `notify`    | Not implemented — dispatcher returns the default `{success: true}` ack. |

---

## Storage layout

```
<VAULT_ADDR>/v1/<VAULT_PATH_PREFIX>/<external_id>
```

- **`VAULT_PATH_PREFIX`** defaults to `secret/data/parameters`. The `data/` segment is the KV v2 convention — change the default if your mount uses KV v1 (drop the `data/`) or a different mount point.
- **`external_id`** is a UUIDv4 generated at store time. It is the canonical handle nullplatform persists and re-injects for retrieve/delete.

The stored payload at each path is a JSON envelope, not the raw value:

```json
{
  "data": {
    "parameter_id": 42,
    "value": "the-actual-value",
    "stored_at": "2026-05-15T12:34:56Z",
    "external_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479"
  }
}
```

Keeping `parameter_id` and `external_id` inside the payload makes orphaned secrets self-describing — if someone discovers a stale entry under `parameters/`, the payload tells them which nullplatform parameter it belongs to.

---

## Configuration

`PROVIDER_CONFIG` shape (populated by `fetch_configuration` if you implement one):

```json
{
  "address":     "https://vault.example.com",
  "token":       "hvs.xxx",
  "path_prefix": "secret/data/parameters"
}
```

Equivalent env vars: `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_PATH_PREFIX`. Provider config wins over env per `get_config_value` priority.

---

## Authentication notes

This provider uses static token auth via `X-Vault-Token`. For production use, consider:

- **Token rotation**: short-lived tokens (issued by AppRole, Kubernetes auth, etc.) should be refreshed by `fetch_configuration` rather than relying on a long-lived `VAULT_TOKEN` env var.
- **OIDC / Kubernetes auth**: a richer `fetch_configuration` could exchange a workload identity for a Vault token at runtime, removing the need for any pre-issued credential.

The operation scripts (`store`/`retrieve`/`delete`) don't care how `VAULT_TOKEN` got into the environment — they just use it. Swap the auth mechanism by changing `setup` (and optionally adding `fetch_configuration`).

---

## Compatibility

The output JSON shape matches the previous `parameters/vault/` implementation byte-for-byte:

- `store` → `{external_id, metadata: {vault_path}}`
- `retrieve` → `{value}` or `{value: "value not found"}`
- `delete` → `{success: true}`

A scope that switches from the old layout to this provider sees no behavior change against Vault.
