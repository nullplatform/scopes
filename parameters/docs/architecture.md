# Parameters Package — Architecture

A pluggable parameter and secret storage layer for nullplatform scopes. The provider for each parameter is chosen by the platform itself (via `provider.specification_id` in the notification payload), and the provider's configuration travels in the same payload.

---

## What problem this solves

nullplatform scopes need to persist parameter values somewhere. Different organizations want different backends:

- AWS-native: Secrets Manager and/or Parameter Store
- Azure-native: Key Vault
- Existing HashiCorp infrastructure: Vault
- Hybrid setups: any combination of the above

A monolithic scope tied to one backend forces fork-and-modify for every variation. This package inverts the relationship: the **dispatch layer is the package**, the **backends are pluggable modules** dropped into `providers/`.

The platform decides which provider handles each parameter — there is no per-environment / per-agent configuration of "which provider to use". The notification payload carries that information directly.

---

## Layered design

```
┌────────────────────────────────────────────────────────────────┐
│  nullplatform sends action notification                        │
│  (NOTIFICATION_ACTION="parameter:<action>", NP_ACTION_CONTEXT) │
└────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│  parameters/entrypoint                                         │
│  - Clean NP_ACTION_CONTEXT, export CONTEXT (= .notification)   │
│  - Pick workflow: workflows/<action>.yaml                      │
│  - Honor OVERRIDES_PATH for consumer-side workflow overrides   │
└────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│  workflows/<action>.yaml                                       │
│  - Step 1: build_context                                       │
│  - Step 2: <action> (store / retrieve / delete / notify)       │
└────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│  parameters/build_context                                      │
│  - Parse CONTEXT → EXTERNAL_ID, PARAMETER_ID, PARAMETER_VALUE  │
│  - Derive PARAMETER_KIND from $CONTEXT.secret                  │
│  - Read $CONTEXT.provider.specification_id                     │
│  - np provider specification read --id <spec_id> → slug        │
│  - ACTIVE_PROVIDER = slug; PROVIDER_DIR = providers/$slug      │
│  - PROVIDER_CONFIG = $CONTEXT.provider.attributes              │
│  - Source providers/$ACTIVE_PROVIDER/setup                     │
└────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│  parameters/<action>  (dispatch)                               │
│  - One-liner: source providers/$ACTIVE_PROVIDER/<action>       │
└────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│  providers/<active_provider>/<action>                          │
│  - Executes the actual backend call (curl, aws, az, ...)       │
│  - Writes JSON result to stdout                                │
└────────────────────────────────────────────────────────────────┘
```

The dispatch layer is **provider-agnostic**. It has zero knowledge of any specific provider's existence. Adding a new provider is strictly additive — no edits to `entrypoint`, `build_context`, `workflows/`, or other providers.

---

## How the provider is chosen

For each parameter, nullplatform stores which provider should handle it. That choice travels with every notification as `provider.specification_id` — a UUID pointing to a "provider specification" entity in nullplatform.

`build_context` resolves this UUID into a slug using the np CLI:

```
np provider specification read --id <specification_id> --output json
→ { "slug": "aws_secret_manager", ... }
```

The slug becomes `ACTIVE_PROVIDER`, which must match a directory under `parameters/providers/`. The match is exact, case-sensitive.

The provider's configuration travels in the same payload at `provider.attributes`. `build_context` exports it as `PROVIDER_CONFIG` (a JSON string). Each provider's `setup` reads from `PROVIDER_CONFIG` via `get_config_value --provider '.field'` to extract specific fields (region, kms_key_id, etc.).

This means **there is no per-environment configuration of "which provider"** — the platform decides per-parameter. A single agent can serve parameters routed to Vault and secrets routed to Secrets Manager at the same time, without any agent-side configuration.

---

## File tree

```
parameters/
├── entrypoint              # Action router (action → workflow)
├── build_context           # Resolves ACTIVE_PROVIDER from spec_id, sources setup
├── store, retrieve,        # Dispatch one-liners
│   delete, notify
├── workflows/              # 4 YAMLs (one per action)
├── utils/
│   ├── get_config_value    # Priority: provider config > env > default
│   └── log                 # All levels route to stderr
├── providers/
│   ├── README.md           # Contract every provider must satisfy
│   ├── hashicorp_vault/    # HTTP API
│   ├── aws_secret_manager/     # aws CLI
│   ├── parameter_store/    # aws CLI (only kind-branching provider)
│   └── azure_key_vault/    # az CLI
├── tests/                  # BATS — mirrors source structure
└── docs/                   # This file, configuration.md, adding_a_provider.md
```

See `parameters/providers/README.md` for the provider contract spec.
See `configuration.md` for the payload shape and how `PROVIDER_CONFIG` is structured.
See `adding_a_provider.md` to drop in a new backend.
