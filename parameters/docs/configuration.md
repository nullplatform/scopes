# Configuration

How the parameters package resolves which provider to use and where each provider gets its config.

---

## Two layers of configuration

### 1. Provider selection (which backend handles this request)

Two env variables:

| Env var              | Purpose                                          |
|----------------------|--------------------------------------------------|
| `SECRET_PROVIDER`    | Which provider handles `kind=secret` requests    |
| `PARAMETER_PROVIDER` | Which provider handles `kind=parameter` requests |

Values are the directory names under `providers/` (e.g. `secret_manager`, `parameter_store`, `hashicorp_vault`, `azure_key_vault`).

**Resolution:** env-only. There is no provider-config fallback for selectors at this layer — that would create a chicken-and-egg problem (build_context needs to know which provider to fetch config from, but the config tells it which provider to use). If you want the platform to drive selectors, populate these env vars in the agent/runner environment before invoking the entrypoint.

### 2. Provider-specific configuration (settings for the chosen backend)

Each provider's `setup` script reads its own config from a combination of env vars and `PROVIDER_CONFIG` (a JSON string scoped to that one provider).

**Resolution priority** (highest to lowest):

1. `PROVIDER_CONFIG` (via `get_config_value --provider '.field'`)
2. Environment variable (via `get_config_value --env NAME`)
3. Default (via `get_config_value --default 'value'`)

`PROVIDER_CONFIG` is populated by the active provider's `fetch_configuration` script (optional). If `fetch_configuration` doesn't exist or doesn't set `PROVIDER_CONFIG`, the provider falls back entirely to env vars.

---

## The four strategies

| Strategy                         | `PARAMETER_PROVIDER` | `SECRET_PROVIDER`      |
|----------------------------------|----------------------|------------------------|
| Full Secrets Manager             | `secret_manager`     | `secret_manager`       |
| Full Parameter Store (cheapest)  | `parameter_store`    | `parameter_store`      |
| Mixed AWS (recommended for AWS)  | `parameter_store`    | `secret_manager`       |
| Full HashiCorp Vault             | `hashicorp_vault`    | `hashicorp_vault`      |
| Full Azure Key Vault             | `azure_key_vault`    | `azure_key_vault`      |
| Hybrid Azure secrets, AWS params | `parameter_store`    | `azure_key_vault`      |

Switching strategies = changing two env vars. Zero code changes.

---

## Per-provider config shapes

The shape of `PROVIDER_CONFIG` for each provider:

### `hashicorp_vault`

```json
{
  "address":     "https://vault.example.com",
  "token":       "hvs.xxx",
  "path_prefix": "secret/data/parameters"
}
```

Equivalent env vars: `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_PATH_PREFIX`.

### `secret_manager`

```json
{
  "region":      "us-east-1",
  "name_prefix": "parameters/",
  "kms_key_id":  "alias/aws/secretsmanager"
}
```

Equivalent env vars: `AWS_REGION` (or `AWS_DEFAULT_REGION`), `SM_NAME_PREFIX`, `SM_KMS_KEY_ID`. `kms_key_id` is optional (defaults to AWS-managed key).

### `parameter_store`

```json
{
  "region":      "us-east-1",
  "name_prefix": "/nullplatform/parameters/",
  "kms_key_id":  "alias/parameters-secure",
  "tier":        "Standard"
}
```

Equivalent env vars: `AWS_REGION`, `PS_NAME_PREFIX`, `PS_KMS_KEY_ID`, `PS_TIER`. `kms_key_id` only matters for `kind=secret` (SecureString). `tier` ∈ {`Standard`, `Advanced`, `Intelligent-Tiering`}.

### `azure_key_vault`

```json
{
  "vault_name":    "my-keyvault",
  "secret_prefix": "parameters-"
}
```

Equivalent env vars: `AZURE_KEY_VAULT_NAME`, `AZURE_KEY_VAULT_SECRET_PREFIX`. Auth comes from the Azure CLI's default credential chain.

---

## How `PROVIDER_CONFIG` gets populated

Each provider may have a `fetch_configuration` script. When `build_context` activates that provider, it sources `providers/<name>/fetch_configuration` before `setup`. The script's job:

1. Fetch the provider's config from wherever it lives.
2. Export `PROVIDER_CONFIG` as a JSON string.

Where the config "lives" is up to each provider:

- **`np provider get`** — call the nullplatform CLI to read providers config.
- **REST call** — query an internal config service.
- **File** — read a mounted config file.
- **Env vars only** — skip `fetch_configuration` entirely; rely on env.

The provider package doesn't care which mechanism you choose. If you want a uniform mechanism across providers, you can implement them all the same way; if you want each to source config differently (e.g. Vault config from Consul, AWS config from instance profile), nothing forces them to align.

---

## Local development

For local testing without wiring `fetch_configuration`, set everything via env vars:

```bash
export SECRET_PROVIDER=hashicorp_vault
export PARAMETER_PROVIDER=hashicorp_vault
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root-token
# ...then invoke the entrypoint
```

All providers fall through to env vars when `PROVIDER_CONFIG` is unset or empty.
