# Parameters Package — Architecture

A pluggable parameter and secret storage layer for nullplatform scopes. Choose any backend per-kind (one provider for plain parameters, another for secrets) without touching code outside provider directories.

---

## What problem this solves

nullplatform scopes need to persist parameter values somewhere. Different organizations want different backends:

- AWS-native shops: AWS Secrets Manager and/or Parameter Store
- Azure-native shops: Azure Key Vault
- Existing HashiCorp infrastructure: Vault
- Hybrid: secrets in one backend, plain parameters in another

A monolithic scope tied to one backend forces fork-and-modify for every variation. This package inverts the relationship: the **dispatch layer is the package**, the **backends are pluggable modules** dropped into `providers/`.

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
│  - No kind discrimination here — that's pushed to build_context │
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
│  - Derive PARAMETER_KIND from $CONTEXT.secret (true/false)     │
│  - Resolve ACTIVE_PROVIDER from SECRET_PROVIDER or PARAMETER_  │
│    PROVIDER env var (per PARAMETER_KIND)                       │
│  - Source providers/$ACTIVE_PROVIDER/fetch_configuration       │
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

## Why two env vars instead of one

`SECRET_PROVIDER` and `PARAMETER_PROVIDER` are separate because the most common production setup uses different backends for each kind:

- Plain parameters in Parameter Store (free Standard tier)
- Secrets in Secrets Manager (per-secret cost, but rotation + replication)

Setting `PARAMETER_PROVIDER=parameter_store` and `SECRET_PROVIDER=secret_manager` is one configuration line that captures this. The dispatcher resolves the right provider per request based on `$CONTEXT.secret`.

If you want a single provider for both kinds, set both env vars to the same value:

```bash
SECRET_PROVIDER=hashicorp_vault
PARAMETER_PROVIDER=hashicorp_vault
```

---

## File tree

```
parameters/
├── entrypoint              # Action router (kind discrimination + workflow selection)
├── build_context           # Provider resolution + sourcing of provider's setup
├── store, retrieve,        # Dispatch one-liners
│   delete, notify
├── workflows/              # 4 unified (store/retrieve/delete/notify)
├── utils/
│   ├── get_config_value    # Priority: provider config > env > default
│   └── log                 # debug/info/warn/error with stderr routing
├── providers/
│   ├── README.md           # Contract every provider must satisfy
│   ├── hashicorp_vault/    # HTTP API
│   ├── secret_manager/     # aws CLI
│   ├── parameter_store/    # aws CLI (the only kind-branching provider)
│   └── azure_key_vault/    # az CLI
├── tests/                  # BATS — mirrors source structure
└── docs/                   # This file, configuration.md, adding_a_provider.md
```

See `parameters/providers/README.md` for the provider contract spec.
See `configuration.md` for how `PROVIDER_CONFIG` is structured and how selectors are resolved.
See `adding_a_provider.md` to drop in a new backend.
