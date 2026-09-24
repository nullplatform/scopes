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

Deployment names use `{.application.slug}-{.scope.slug}-{.deployment.id}`; scope-level names (ingress, HTTPRoute, cert) use `{.application.slug}-{.scope.slug}-{.scope.id}`. Long slugs are trimmed evenly to fit the naming budget — the numeric id is never trimmed.

### `custom`

Same rendering engine as `qualified`, but the patterns themselves come from configuration: `naming.deployment_pattern` and `naming.scope_pattern` on the `container-orchestration` or `scope-configurations` provider. Each `{...}` segment is a jq path evaluated against the run's `CONTEXT`, so a pattern can reach any field visible there — including capabilities and other metadata, not just the fixed set below.

```
naming.deployment_pattern: "{.namespace.slug}-{.application.slug}-{.deployment.id}"
deployment:                  payments-checkout-api-789012
```

A custom pattern should contain its discriminant in the canonical dotted form — `{.deployment.id}` for the deployment pattern, `{.scope.id}` for the scope pattern — since without a unique id, a new deployment would overwrite the previous one's objects. When the discriminant is present, anywhere in the pattern, it is rendered exactly as written. When it is absent, it is appended (`-{.deployment.id}` or `-{.scope.id}`) as a fixed segment that is never trimmed, and a line on stderr reports the append and the effective pattern used — this never fails silently. Placeholders must be separated by a single hyphen; any other literal between two placeholders is rejected, as is a pattern whose fixed literals and ids leave fewer than 3 characters for each remaining slug.

Only dotted field access and bracketed quoted keys are accepted inside `{...}` — roughly `.foo.bar` or `.foo["bar-baz"]` — never arbitrary jq (no pipes, filters or variable bindings). The path is rejected before it is ever evaluated, since it is interpolated into a jq program.

## Fixed versus flexible

Whether a resolved value is trimmed to fit the naming budget is decided by the value, not by the path: **a resolved value matching `^[0-9]+$` is fixed and never trimmed; everything else is flexible** and shrinks evenly with the other flexible segments when the pattern is too long. This needs no extra syntax because nullplatform ids are numeric and slugs cannot be — a Kubernetes name must start with a letter, so a slug is never all digits.

```
{.application.slug}-{.scope.slug}-{.deployment.id}
```

Here `{.application.slug}` and `{.scope.slug}` are flexible; `{.deployment.id}` is fixed because `deployment.id` resolves to a number.

## Naming budget

| Object family | Budget | Configured via |
|---|---|---|
| Deployment-scoped names (Deployment, HPA, PDB, Secret, CronJob) | 46 characters by default | `NAMING_MAX_LENGTH` env var, or `naming.max_length` on the `container-orchestration`/`scope-configurations` provider |
| Scope-scoped names (Ingress, HTTPRoute, serving cert) | 52 characters, fixed | not configurable |

The deployment budget defaults to 46 rather than Kubernetes' 63-character object-name limit because the platform appends a further suffix to derive the ReplicaSet and Pod names (`-<replicaset-hash>-<pod-hash>`, up to 17 characters) — a Deployment name that used the full 63 characters would produce Pod names Kubernetes rejects.

## Existing scope objects are never renamed

Switching a scope's `NAMING_STRATEGY` (or editing a `custom` pattern) does not rename objects that already exist. Before computing a scope-scoped name, `np_naming_roles_patterned` looks for an existing Ingress or HTTPRoute carrying the scope's `scope_id` label (`np_naming_discover_scope`); if one is found, its name is kept as-is instead of being recomputed from the new pattern.

This asymmetry is deliberate and only applies to scope-scoped names. Deployment-scoped names (Deployment, Service, HPA, PDB, Secret, CronJob) for a *newly created* deployment are always computed fresh from the current strategy — a deployment already gets a new set of objects per deployment, so there is nothing to freeze there.

The blue deployment during a rollback or during finalize's cleanup is the one exception: `np_naming_apply_to_context` (used by `build_blue_deployment` and `rollback_traffic`) discovers the blue's live object names by `deployment_id` label instead of recomputing them from whatever strategy is active now, falling back to the `ids` formula only when discovery finds nothing. Without this, a blue created under one strategy and rolled back to after a strategy change would route traffic to, or try to delete, an object that was never created.

## Known limitations

scheduled_task's `cronjob.*` metrics (`execution_count`, `success_count`, `failure_count`, `cpu_usage`, `memory_usage`) match Prometheus series by parsing the scope id back out of the job/pod name with a `job-${SCOPE_ID}-.*` regex. Under `qualified` or `custom`, job and pod names carry the application and scope slugs instead of that fixed shape, so the regex stops matching and these metrics return no data.

Freezing (both the scope's main object and its per-port objects) only checks two name generations: the hardcoded `ids` formula and the currently active pattern. Nothing persists a scope's naming history, so a scope that has moved through more than one strategy change (e.g. `ids` → `qualified` → `custom`) can still orphan a per-port object named under an intermediate generation — it matches neither the legacy formula nor the current one, so a fresh name gets computed and applied alongside the untouched, now-unreferenced original. Closing this properly needs persisted per-object name history, which this design deliberately does not keep.

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
- `k8s/naming/tests/pattern.bats` covers pattern validation (discriminant, unsafe paths, separator, literal budget) and the `custom` strategy.
- `k8s/naming/tests/discover.bats` covers `np_naming_lookup`, `np_naming_discover_blue`, `np_naming_discover_scope`, and the existing-scope-name freeze behavior.
