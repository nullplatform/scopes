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

`<provider_name>` is `snake_case` and is what users will set in `SECRET_PROVIDER` / `PARAMETER_PROVIDER`.

---

## Step 2: Write `setup`

Validate config and export connection handles. Don't repeat this in operation scripts — `setup` is the DRY anchor.

```bash
#!/bin/bash
set -euo pipefail

# Read config (provider config wins, env fallback, defaults last)
MY_ENDPOINT=$(get_config_value --env MY_ENDPOINT --provider '.endpoint')
MY_TOKEN=$(get_config_value --env MY_TOKEN --provider '.token')
MY_PREFIX=$(get_config_value --env MY_PREFIX --provider '.prefix' --default 'parameters-')

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

## Step 4: Write `fetch_configuration` (optional)

If the platform stores your provider's config somewhere fetchable, add a `fetch_configuration` script that exports `PROVIDER_CONFIG` as a JSON string with the shape your `setup` expects.

```bash
#!/bin/bash
# providers/<provider_name>/fetch_configuration
PROVIDER_CONFIG=$(np provider get --type <something> --output json)
export PROVIDER_CONFIG
```

If you skip this file, `PROVIDER_CONFIG` stays unset and `setup` reads everything from env vars.

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

1. Set the env var: `SECRET_PROVIDER=<provider_name>` and/or `PARAMETER_PROVIDER=<provider_name>`.
2. If using `fetch_configuration`, the platform team needs to ensure the fetch mechanism (np CLI, REST endpoint, etc.) returns the JSON shape your provider expects.

Done. The new provider is reachable from every workflow without any other change.

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
