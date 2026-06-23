# Configuration

How the parameters package decides which provider to use and where each provider gets its config — all from the notification payload.

---

## Where everything comes from

Each notification from nullplatform includes the full information needed to handle the parameter:

| Field in `$CONTEXT` | Purpose |
|---|---|
| `parameter_id` | nullplatform parameter ID |
| `value` | the value to persist (only on store) |
| `external_id` | provider's handle for the parameter (on retrieve/delete/notify) |
| `secret` | bool — discriminates secret vs plain parameter |
| `parameter_name` | human-readable name |
| `encoding` | encoding of the value (`plain`, `base64`, etc.) |
| `entities` | NRN parsed into entity IDs (organization, account, namespace, application) |
| `dimensions` | optional object — parameter scoping (env, country, etc.) |
| **`provider.specification_id`** | **UUID identifying which provider handles this parameter** |
| **`provider.attributes`** | **Provider-specific configuration (region, vault address, etc.)** |
| `provider.nrn` | Provider-instance NRN (informational) |
| `provider.dimensions` | Provider-instance dimensions (informational, different from parameter dimensions) |
| `provider.id` | Provider-instance ID (informational) |

The two fields that drive the dispatch are `provider.specification_id` (which provider) and `provider.attributes` (its config).

---

## Provider resolution

`build_context` calls:

```bash
np provider specification read --id <provider.specification_id> --output json
```

The response includes a `slug` field. That slug must match the name of a directory under `parameters/providers/`. For example:

| Slug returned | Provider directory used |
|---|---|
| `hashicorp_vault` | `parameters/providers/hashicorp_vault/` |
| `aws_secret_manager` | `parameters/providers/aws_secret_manager/` |
| `parameter_store` | `parameters/providers/parameter_store/` |
| `azure_key_vault` | `parameters/providers/azure_key_vault/` |

If the slug doesn't match any installed provider, `build_context` fails with a list of available providers and instructions to either rename the spec slug or add the missing provider.

---

## Provider config

`build_context` exports `PROVIDER_CONFIG` as a JSON string containing whatever is in `$CONTEXT.provider.attributes`. The shape is provider-specific.

Each provider's `setup` script reads from `PROVIDER_CONFIG` via `get_config_value`:

```bash
REGION=$(get_config_value --env AWS_REGION --provider '.region')
```

Priority order (highest to lowest):

1. Provider config (`get_config_value --provider '.field'`)
2. Environment variable (`get_config_value --env NAME`)
3. Default (`get_config_value --default 'value'`)

Env vars take precedence ONLY when the provider attribute is missing. This lets you override config in a local dev environment by setting env vars while keeping the platform-controlled config as the production source of truth.

---

## Per-provider config shapes

The shape of `$CONTEXT.provider.attributes` for each provider:

### `hashicorp_vault`

```json
{
  "address":     "https://vault.example.com",
  "token":       "hvs.xxx",
  "path_prefix": "secret/data/parameters"
}
```

### `aws_secret_manager` (currently named `aws_secret_manager`)

```json
{
  "region":      "us-east-1",
  "name_prefix": "parameters/",
  "kms_key_id":  "alias/aws/secretsmanager"
}
```

`kms_key_id` is optional (defaults to AWS-managed key).

### `parameter_store`

```json
{
  "region":      "us-east-1",
  "name_prefix": "/nullplatform/parameters/",
  "kms_key_id":  "alias/parameters-secure",
  "tier":        "Standard"
}
```

`kms_key_id` only matters for `kind=secret` (SecureString). `tier` ∈ {`Standard`, `Advanced`, `Intelligent-Tiering`}.

### `azure_key_vault`

```json
{
  "vault_name":    "my-keyvault",
  "secret_prefix": "parameters-"
}
```

Authentication comes from the Azure CLI's default credential chain.

---

## What's NOT in this package

Two things that used to be design points but are obsolete now:

- **`SECRET_PROVIDER` / `PARAMETER_PROVIDER` env vars** — not needed. The platform sends `specification_id` per parameter, so there's no global "which provider to use" setting.
- **`fetch_configuration` scripts per provider** — not needed. Config comes in the payload as `provider.attributes`, no separate fetching step.

Providers can still be tested locally with env vars (e.g., `VAULT_ADDR=http://localhost:8200`) because `get_config_value` falls back to env when `PROVIDER_CONFIG` doesn't have the field. This is useful for development without involving the platform.

---

## Local development

For local testing without involving the platform, set the relevant env vars and use a stubbed `np` CLI that returns a known slug:

```bash
# Stub np in PATH
cat > /tmp/np << 'EOF'
#!/bin/bash
echo '{"slug": "hashicorp_vault"}'
EOF
chmod +x /tmp/np
export PATH=/tmp:$PATH

# Set the provider's env vars
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root-token

# Now invoke the entrypoint
NP_ACTION_CONTEXT='...' NOTIFICATION_ACTION='parameter:store' ./parameters/entrypoint
```

All providers fall through to env vars when `PROVIDER_CONFIG` is missing fields, making local-only iteration possible.
