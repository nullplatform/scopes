# Adding a New Provider

Step-by-step guide to add a new backend (e.g. Google Secret Manager, Doppler, 1Password Secrets Automation).

The parameters package is designed so that adding a provider is **strictly additive**. You drop a directory under `providers/`; nothing outside it changes.

---

## What you need to know about the backend

Before you start, answer these questions:

| Question                                                | Why it matters                                  |
|---------------------------------------------------------|-------------------------------------------------|
| What CLI / API do you call?                             | Determines your tooling (curl, aws, az, gcloud) |
| How does authentication work?                           | Defines what `setup` validates                  |
| What's the naming convention for stored items?          | Defines your prefix + UUID scheme               |
| Does it have soft-delete?                               | Determines if `delete` needs a purge step       |
| Does it distinguish secret vs plain types at the API?   | Determines if `store` branches on PARAMETER_KIND |

---

## Step 1: Create the provider directory

```bash
mkdir -p parameters/providers/<provider_name>/docs
mkdir -p parameters/tests/providers/<provider_name>
```

`<provider_name>` must match the `slug` field of the `parameters-storage` provider specification you (or the platform admin) registered in nullplatform. The agent's `build_context` calls `np provider specification read --id <specification_id>`, reads `.slug`, and uses it to find your directory.

---

## Step 2: Write `setup`

Validate config and export connection handles. Don't repeat this in operation scripts — `setup` is the DRY anchor.

Config values can come from **two sources**, and `get_config_value` picks whichever is present (provider config wins, env fallback, defaults last):

1. **`parameters-storage` provider in nullplatform** — values set when the provider is registered, sent to the agent in `$CONTEXT.provider.attributes`. Good for non-sensitive operational settings (region, name prefix, vault address, etc.).
2. **Environment variables on the agent** — set by the operator outside nullplatform. **Recommended for credentials, tokens, and any sensitive material** that should not be stored in nullplatform's database. This keeps ownership of sensitive data 100% on the operator side and lets them use their own protection mechanisms (secret stores, rotation, etc.).

```bash
#!/bin/bash
set -euo pipefail

# Read config (provider config wins, env fallback, defaults last)
MY_ENDPOINT=$(get_config_value --env MY_ENDPOINT --provider '.endpoint')
# Token: only env var — do NOT pass via provider config (keep credentials off-platform)
MY_TOKEN=$(get_config_value --env MY_TOKEN)
MY_PREFIX=$(get_config_value --env MY_PREFIX --provider '.prefix' --default 'nullplatform-')

if [ -z "$MY_ENDPOINT" ]; then
  log error "❌ <Backend> endpoint not configured"
  log error ""
  log error "💡 Possible causes:"
  log error "   • MY_ENDPOINT env var is not set"
  log error "   • .endpoint is missing in PROVIDER_CONFIG"
  log error ""
  log error "🔧 How to fix:"
  log error "   • Set MY_ENDPOINT=<value>"
  exit 1
fi

# Validate format / shape if relevant
# ...

export MY_ENDPOINT MY_TOKEN MY_PREFIX
```

---

## Step 3: Write the four operation scripts

### `store`

Generate a UUID, persist the value, return `{external_id, metadata}`.

```bash
#!/bin/bash
set -euo pipefail

EXTERNAL_ID=$(uuidgen 2>/dev/null || echo "$(openssl rand -hex 16 | sed 's/\(.{8}\)\(.{4}\)\(.{4}\)\(.{4}\)\(.{12}\)/\1-\2-\3-\4-\5/')")
NAME="${MY_PREFIX}${EXTERNAL_ID}"

if ! HANDLE=$(my_cli create --endpoint "$MY_ENDPOINT" --name "$NAME" --value "$PARAMETER_VALUE" 2>/dev/null); then
  log error "❌ Failed to store in <Backend>"
  log error ""
  log error "💡 Possible causes:"
  log error "   • <causes specific to the backend>"
  log error ""
  log error "🔧 How to fix:"
  log error "   • <commands to verify identity / connectivity>"
  exit 1
fi

jq -n \
  --arg external_id "$EXTERNAL_ID" \
  --arg handle "$HANDLE" \
  --arg name "$NAME" \
  '{external_id: $external_id, metadata: {handle: $handle, name: $name}}'
```

If your backend distinguishes types (like `parameter_store` does with String/SecureString), branch on `PARAMETER_KIND` here.

### `retrieve`

Read the value, return `{value}` or `{value: "value not found"}` on miss.

```bash
#!/bin/bash
set -euo pipefail

NAME="${MY_PREFIX}${EXTERNAL_ID}"

if VALUE=$(my_cli get --endpoint "$MY_ENDPOINT" --name "$NAME" 2>/dev/null); then
  jq -n --arg value "$VALUE" '{value: $value}'
else
  echo '{
      "value": "value not found"
    }'
fi
```

### `delete`

Always returns `{success: true}`. Suppress errors with `|| true`.

```bash
#!/bin/bash
set -euo pipefail

NAME="${MY_PREFIX}${EXTERNAL_ID}"

my_cli delete --endpoint "$MY_ENDPOINT" --name "$NAME" >/dev/null 2>&1 || true

echo '{
  "success": true
}'
```

### `notify` (optional)

Skip the file unless your backend needs a per-notify side effect. The dispatch returns the default `{success: true}` if `notify` doesn't exist.

---

## Step 5: Write tests

Mirror the source structure under `parameters/tests/providers/<provider_name>/`:

```
tests/providers/<provider_name>/
├── setup.bats       # Config resolution, validation, error paths
├── store.bats       # JSON output shape, CLI args, error paths
├── retrieve.bats    # Hit case, miss case, CLI args
└── delete.bats      # Always-success, CLI args, idempotency
```

Use the patterns from existing providers (`hashicorp_vault`, `aws_secret_manager`, `parameter_store`, `azure_key_vault`):

- Mock the backend CLI as a script in `$BATS_TEST_TMPDIR/bin/`, export PATH to find it.
- Capture CLI args to a log file, assert on them.
- Mock `uuidgen` for deterministic `external_id` in store tests.
- Use the `DEPS="source $PARAMETERS_DIR/utils/log"` pattern to make `log` available in `bash -c` subshells.

Aim for at least these scenarios per provider:

| Script    | Required tests                                                              |
|-----------|-----------------------------------------------------------------------------|
| setup     | Missing required config fails with troubleshooting; PROVIDER_CONFIG wins over env; defaults applied |
| store     | Output JSON shape; CLI called with correct args; failure path returns non-zero with troubleshooting |
| retrieve  | Hit returns value; miss returns "value not found"                           |
| delete    | Returns `{success: true}`; idempotent on CLI failure                        |

---

## Step 6: Write the docs

Add at least `parameters/providers/<provider_name>/docs/architecture.md` describing:

- Storage layout (naming, prefix, encryption model)
- Cost model
- Authentication
- Any quirks (soft-delete, regions, multi-tenant constraints)

If the backend needs IAM-style permissions (AWS, GCP), add `iam-policy.md` with a least-privilege example using placeholders for accounts/regions/keys.

---

## Step 7: Wire it up

1. Register a `parameters-storage` provider in nullplatform with `slug: <provider_name>` and the schema for your provider's config attributes (use a `.json.tpl` file as the spec — see existing providers for examples).
2. Bind parameters in nullplatform to that provider specification.

Done. The agent receives `provider.specification_id` and `provider.attributes` in every notification for those parameters; `build_context` resolves the slug, finds your directory, and dispatches.

---

## Checklist

Before considering a new provider complete:

- [ ] `setup` validates config and exits with troubleshooting on missing fields
- [ ] `store` outputs `{external_id, metadata}` JSON
- [ ] `retrieve` outputs `{value}` (or `{value: "value not found"}`)
- [ ] `delete` outputs `{success: true}` (always — idempotent)
- [ ] Scripts use `set -euo pipefail`
- [ ] Errors go to stderr via `log error "..."`
- [ ] No stdout output other than the final JSON
- [ ] Every error has `💡 Possible causes:` and `🔧 How to fix:` blocks
- [ ] BATS tests cover setup error paths, store output shape, retrieve hit/miss, delete idempotency
- [ ] `architecture.md` documents storage layout and cost
- [ ] If the backend has IAM, `iam-policy.md` shows least-privilege scoping
