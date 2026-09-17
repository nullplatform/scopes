# Resource Naming

The k8s scope names every Kubernetes object it creates — `Deployment`, `Service`, `HPA`, `PodDisruptionBudget`, `Secret`, `CronJob`, `Ingress`/`HTTPRoute` — from a `NAMING_STRATEGY` chosen per scope. All object names are resolved once per run in `k8s/naming/resolve_names` (`np_naming_resolve`) and written onto `.names.*` in `CONTEXT`, so every template and every operational script (pause/resume autoscaling, restart pods, kill instance, scale deployments) reads names from the same place instead of constructing them independently.

Operational scripts that need to find an *already-running* object (an HPA, a Deployment) never reconstruct its name either — they look it up by the `deployment_id` label with `np_naming_lookup`, so a lookup keeps working across strategies and across a scope migrated from one strategy to another.

## Strategies

Set the strategy via the `container-orchestration` or `scope-configurations` provider's `naming.strategy`, or the `NAMING_STRATEGY` env var. Provider values win over the env var; both win over the default.

### `ids` (default)

Names objects from raw scope and deployment ids, exactly as the scope has always done. No behavior changes for existing scopes.

```
deployment:     d-123456-789012
hpa:            hpa-d-123456-789012
scope_ingress:  k-8-s-production-123456-internet-facing
```

### `qualified`

Names objects from the application and scope slugs plus the numeric id, so an object's name says what it is instead of just carrying an opaque id.

```
deployment:     checkout-api-production-789012
hpa:            hpa-checkout-api-production-789012
scope_ingress:  checkout-api-production-123456
```

Deployment names use `{application}-{scope}-{deployment_id}`; scope-level names (ingress, HTTPRoute, cert) use `{application}-{scope}-{scope_id}`. Long slugs are trimmed evenly to fit the naming budget — the numeric id is never trimmed.

### `custom`

Same rendering engine as `qualified`, but the patterns themselves come from configuration: `naming.deployment_pattern` and `naming.scope_pattern` on the `container-orchestration` or `scope-configurations` provider.

```
naming.deployment_pattern: "{namespace}-{application}-{deployment_id}"
deployment:                 payments-checkout-api-789012
```

A custom pattern must contain its discriminant (`{deployment_id}` for the deployment pattern, `{scope_id}` for the scope pattern) — without it, a new deployment would overwrite the previous one's objects. Placeholders must be separated by a single hyphen; any other literal between two placeholders is rejected, as is a pattern whose fixed literals and ids leave fewer than 3 characters for each remaining slug.

## Placeholders

| Placeholder | Kind | Source |
|---|---|---|
| `{application}` | slug | `application.slug` |
| `{scope}` | slug | `scope.slug` |
| `{namespace}` | slug | `namespace.slug` |
| `{account}` | slug | `account.slug` |
| `{deployment_id}` | fixed id | `deployment.id` |
| `{scope_id}` | fixed id | `scope.id` |
| `{application_id}` | fixed id | `application.id` |
| `{namespace_id}` | fixed id | `namespace.id` |

Slug placeholders are trimmed to fit the naming budget when a pattern is too long; fixed-id placeholders are never trimmed and always count against the budget in full.

## Naming budget

| Object family | Budget | Configured via |
|---|---|---|
| Deployment-scoped names (Deployment, HPA, PDB, Secret, CronJob) | 46 characters by default | `NAMING_MAX_LENGTH` env var, or `naming.max_length` on the `container-orchestration`/`scope-configurations` provider |
| Scope-scoped names (Ingress, HTTPRoute, serving cert) | 52 characters, fixed | not configurable |

The deployment budget defaults to 46 rather than Kubernetes' 63-character object-name limit because the platform appends a further suffix to derive the ReplicaSet and Pod names (`-<replicaset-hash>-<pod-hash>`, up to 17 characters) — a Deployment name that used the full 63 characters would produce Pod names Kubernetes rejects.

## Existing scope objects are never renamed

Switching a scope's `NAMING_STRATEGY` (or editing a `custom` pattern) does not rename objects that already exist. Before computing a scope-scoped name, `np_naming_roles_patterned` looks for an existing Ingress or HTTPRoute carrying the scope's `scope_id` label (`np_naming_discover_scope`); if one is found, its name is kept as-is instead of being recomputed from the new pattern.

This asymmetry is deliberate and only applies to scope-scoped names. Deployment-scoped names (Deployment, HPA, PDB, Secret, CronJob) are always computed fresh from the current strategy — a deployment already gets a new set of objects per deployment, so there is nothing to freeze.

## Known limitations

scheduled_task's `cronjob.*` metrics (`execution_count`, `success_count`, `failure_count`, `cpu_usage`, `memory_usage`) match Prometheus series by parsing the scope id back out of the job/pod name with a `job-${SCOPE_ID}-.*` regex. Under `qualified` or `custom`, job and pod names carry the application and scope slugs instead of that fixed shape, so the regex stops matching and these metrics return no data.

## Implementation Map

- Name resolution engine, strategies and discovery: `k8s/naming/resolve_names`
- Wired into scope context: `k8s/scope/build_context` (look for `np_naming_resolve`)
- Wired into deployment context (blue discovery): `k8s/deployment/build_context` (look for `np_naming_discover_blue`)
- Label-based lookups used by operational scripts: `k8s/scope/pause_autoscaling`, `k8s/scope/resume_autoscaling`, `k8s/scope/set_desired_instance_count`, `k8s/deployment/scale_deployments`, `k8s/deployment/kill_instance`, `k8s/deployment/wait_deployment_active`
- Example `NAMING_STRATEGY` configuration: `k8s/values.yaml`

## Tests

- `k8s/naming/tests/golden.bats` renders all fifteen templates under the default `ids` strategy and diffs them byte-for-byte against a captured baseline, so a naming change can never silently alter today's names.
- `k8s/naming/tests/resolve.bats` and `k8s/naming/tests/trim.bats` cover the `ids` strategy and the slug-trimming engine.
- `k8s/naming/tests/qualified.bats` covers the `qualified` strategy, including the naming-budget precedence chain and the pod/CronJob length ceilings.
- `k8s/naming/tests/pattern.bats` covers pattern validation (discriminant, unknown placeholders, separator, literal budget) and the `custom` strategy.
- `k8s/naming/tests/discover.bats` covers `np_naming_lookup`, `np_naming_discover_blue`, `np_naming_discover_scope`, and the existing-scope-name freeze behavior.
