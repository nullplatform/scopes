# AWS Secrets Manager — Architecture

This document describes how the `parameters/providers/aws_secret_manager/` provider stores, retrieves, and deletes nullplatform parameters using AWS Secrets Manager (SM).

---

## Role in the parameter lifecycle

A nullplatform parameter has a `kind` that decides where its values are persisted:

| Kind                  | Storage location                         | This provider |
|-----------------------|------------------------------------------|---------------|
| `nullplatform-storage` | nullplatform's own datastore             | Not involved  |
| `third-party-storage`  | External provider (AWS SM, Vault, etc.)  | Used          |

This provider handles parameters configured for third-party storage that the platform routes to AWS Secrets Manager. The platform's choice is per-parameter, and a single parameter — secret or not — can be routed here. Routing a non-secret parameter to AWS SM is supported but costlier than alternatives like Parameter Store; the choice is the platform operator's.

The interaction is event-driven via four actions:

| Action     | Trigger                                          | Effect on AWS SM                                   |
|------------|--------------------------------------------------|----------------------------------------------------|
| `store`    | A parameter value is created or updated          | `CreateSecret` first time, `PutSecretValue` otherwise (new version) |
| `retrieve` | A consumer needs the value                       | `GetSecretValue`, returns the AWSCURRENT version   |
| `delete`   | The parameter is deleted                         | `DeleteSecret --force-delete-without-recovery`      |
| `notify`   | nullplatform-side ack hook                       | No-op (returns `{success: true}`)                  |

---

## Naming strategy

Every secret name is composed from the parameter's NRN entities (with slugs and IDs), its dimensions, and the parameter name + ID:

```
nullplatform/organization=<slug>-<id>/account=<slug>-<id>/.../<dim_key>=<dim_value>/<parameter_name>-<parameter_id>
```

The path follows the **human-friendliness principle**: anyone entering the AWS Secrets Manager console must be able to find the secret by knowing the parameter's context, without consulting nullplatform metadata.

### Example

For a parameter with:

- Entities: `organization=1255165411`, `account=95118862`, `namespace=37094320`, `application=321402625`
- Dimensions: `environment=production`, `country=argentina`
- Parameter: `name=DB_PASSWORD`, `id=42`

The secret name is:

```
nullplatform/organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/country=argentina/environment=production/DB_PASSWORD-42
```

Notes:

- **Slug-id format** (`<slug>-<id>`): slugs are human-readable, IDs are stable. Combining both gives both readability and resilience to potential slug rename support in the future.
- **Slugs are fetched via `np <entity> read --id <id> --format json --query '.slug'`** in parallel during the `store` operation.
- **Dimensions are sorted alphabetically by key** for determinism — the same (NRN, dimensions, parameter) tuple always produces the same secret name.
- **`parameter_name-parameter_id`** at the end: name for legibility, ID for uniqueness across renames.

### IAM anchor

The fixed `nullplatform/` prefix is the IAM scoping anchor:

```
arn:aws:secretsmanager:<region>:<account>:secret:nullplatform/*
```

A single ARN pattern covers everything this provider creates, without granting account-wide access. See `iam-policy.md`.

### ARN suffix

AWS SM appends a random 6-character suffix to every secret ARN:

```
arn:aws:secretsmanager:<region>:<account>:secret:nullplatform/.../DB_PASSWORD-42-XXXXXX
```

Use the wildcard form (`nullplatform/*`) in IAM policies — exact ARN matches without the suffix will not match.

---

## Versioning

nullplatform parameter values are **immutable**. Each update of the same (parameter_id, NRN, dimensions) tuple creates a new VERSION of the same value, not a new value.

AWS Secrets Manager has native version retention. We use it as the source of truth:

- **First `store`** for a given external_id → `CreateSecret`. A new secret is created with version 1.
- **Subsequent `store`** for the same external_id → `PutSecretValue`. A new version is appended, and `AWSCURRENT` moves to it.
- **All previous versions are retained inside the same secret** (up to AWS SM's 100-version cap, after which the oldest unlabeled versions are pruned automatically).

### Why this matters for cost

AWS SM charges $0.40 per secret per month, **regardless of version count**. Putting versions in the same secret is essentially free; creating a new secret per version would multiply cost linearly with update frequency. The implementation enforces the cheap path.

### Why this matters for history

Storing all versions in a single secret means operators can view and (with the right API call) restore older values. The version history is the audit trail.

---

## Secret payload shape

The value stored in AWS SM is a JSON envelope, not the raw value:

```json
{
  "parameter_id": 42,
  "value": "the-actual-secret-value",
  "stored_at": "2026-06-23T12:34:56Z",
  "external_id": "organization=acme-1255165411/.../DB_PASSWORD-42",
  "managed_by": "nullplatform"
}
```

| Field          | Purpose                                                      |
|----------------|--------------------------------------------------------------|
| `parameter_id` | nullplatform parameter ID (reverse lookup)                   |
| `value`        | The actual stored value                                      |
| `stored_at`    | UTC timestamp of this version (audit trail)                  |
| `external_id`  | Canonical handle nullplatform persists (matches secret name) |
| `managed_by`   | Always `"nullplatform"` — identifies the secret as platform-owned |

Each version of the secret carries its own `stored_at` and the value that was active at that point in time.

The secret is also tagged at creation time with `managed_by=nullplatform`. This is visible in the AWS console and usable in IAM resource conditions.

---

## Lifecycle notes

### Hard delete

`delete` uses `--force-delete-without-recovery`. This bypasses AWS SM's default 7–30 day soft-delete window. The trade-off:

- Recoverability after deletion: lost.
- Cost: no longer paying for soft-deleted secrets.
- Name reuse: immediate.

For nullplatform's model — where the version history is the recovery mechanism, not the soft-delete window — this is the right default. An operator who needs the soft-delete window can override via provider config (future extension).

### Error handling

| Error condition                        | `store`           | `retrieve`               | `delete`           |
|----------------------------------------|-------------------|--------------------------|--------------------|
| Resource exists (on store)             | New version added | N/A                      | N/A                |
| ResourceNotFoundException              | N/A               | `{value: "value not found"}` | Idempotent success |
| Any other error (IAM, network, region) | Exit 1 + troubleshooting | Exit 1 + troubleshooting | Exit 1 + troubleshooting |

Only `ResourceNotFoundException` is treated as idempotent success. Every other error — particularly IAM permission failures — propagates as a real error with troubleshooting guidance. Silent success on permission failures would lead to "the parameter says deleted but the secret is still there" bugs.

### Encryption at rest

All values are encrypted by AWS SM. By default, SM uses the AWS-managed KMS key `aws/secretsmanager`. To use a customer-managed KMS key (CMK), set `kms_key_id` in the provider's configuration; the agent then grants `kms:Decrypt` and `kms:GenerateDataKey` on that key (see `iam-policy.md`).
