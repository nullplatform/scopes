# CLIEN-781 — Configurable CPU & RAM limits for k8s scope

Status: design approved (2026-05-21)
Ticket: https://nullplatform.atlassian.net/browse/CLIEN-781
Client: Spin
Assignee: Federico Maleh

## Context

Today the k8s scope exposes two capabilities — `ram_memory` and `cpu_millicores` — that are used as **both** the Kubernetes request and the Kubernetes limit. The Spin team needs to decouple them so that limits can be set higher than requests when desired, while keeping the default behavior unchanged for existing scopes.

The risk that drives the UI shape: a memory `limit > request` increases the chance the scheduler/OOMKiller kills a pod under pressure. So memory limit is a sharp tool that should be hidden behind an "advanced" surface, not the main form.

## Goals

1. Add `cpu_millicores_limit` and `ram_memory_limit` as optional capabilities.
2. Keep the main form intact — `ram_memory` (request) stays at the top, untouched.
3. Group the new fields with the existing `cpu_millicores` in a renamed `Resources` tab inside the collapsable "ADVANCED" categorization.
4. Validate `limit >= request` at the JSON schema layer.
5. Be backwards compatible: missing or null limit ⇒ fall back to the request value, matching today's render.

## Non-goals

- No change to `ram_memory` or `cpu_millicores` themselves (same field types, same defaults).
- No cross-scope validation.
- No docsite update in this ticket (separate PR if requested).
- No CLI/API change beyond what naturally happens by adding properties to the scope spec.

## UI design

### Form layout (after the change)

```
Main form
├─ RAM Memory                    (request, dropdown — unchanged)
└─ Visibility

▼ ADVANCED
├─ Resources                     ← renamed from "Processor"
│   ├─ CPU Millicores            (request — existing)
│   ├─ CPU Millicores Limit      ← NEW (optional integer)
│   └─ RAM Memory Limit          ← NEW (dropdown with "Same as request")
├─ Size & Scaling
├─ Exposed Ports
├─ Scheduled Stop
├─ Protocol
├─ Continuous deployment
└─ Health Check
```

Asymmetry between RAM and CPU is intentional: RAM request stays in the main form (everyone tunes it), RAM limit lives in `Resources` (sharp tool). CPU request and CPU limit both live in `Resources` (CPU was already advanced).

### Tab rename rationale

`Resources` follows Kubernetes vocabulary (`resources: requests/limits`) and is generic enough to host both CPU and memory tuning. Alternatives considered (`Compute`, `Compute & Limits`) were rejected as less standard.

## Schema changes — `k8s/specs/service-spec.json.tpl`

### New properties (siblings of the existing ones)

```json
"cpu_millicores_limit": {
  "type": ["integer", "null"],
  "title": "CPU Millicores Limit",
  "default": null,
  "maximum": 4000,
  "minimum": { "$data": "1/cpu_millicores" },
  "description": "Maximum CPU the container can use. Leave empty to use the same value as the request."
},
"ram_memory_limit": {
  "type": ["integer", "null"],
  "title": "RAM Memory Limit",
  "default": null,
  "oneOf": [
    { "const": null,  "title": "Same as request" },
    { "const": 64,    "title": "64 MB" },
    { "const": 128,   "title": "128 MB" },
    { "const": 256,   "title": "256 MB" },
    { "const": 512,   "title": "512 MB" },
    { "const": 1024,  "title": "1 GB" },
    { "const": 2048,  "title": "2 GB" },
    { "const": 4096,  "title": "4 GB" },
    { "const": 8192,  "title": "8 GB" },
    { "const": 16384, "title": "16 GB" }
  ],
  "minimum": { "$data": "1/ram_memory" },
  "description": "Maximum memory the container can use. Setting this higher than the request increases OOMKill risk."
}
```

Neither property is added to the `required` array of `attributes.schema` — both are optional.

### uiSchema changes

Two edits in the existing `Categorization` block:

1. Change `"label": "Processor"` → `"label": "Resources"`.
2. Add two `Control` entries inside that category's `elements`:

```json
{
  "type": "Category",
  "label": "Resources",
  "elements": [
    { "type": "Control", "label": "CPU Millicores",       "scope": "#/properties/cpu_millicores" },
    { "type": "Control", "label": "CPU Millicores Limit", "scope": "#/properties/cpu_millicores_limit" },
    { "type": "Control", "label": "RAM Memory Limit",     "scope": "#/properties/ram_memory_limit" }
  ]
}
```

No SHOW/HIDE rules are needed — the "Same as request" option (RAM) and empty value (CPU) act as the no-op state.

## Validation

`minimum` with `$data` references the sibling request field. JSON Schema only applies `minimum` to numeric instances, so `null` (or missing) values skip the check naturally — no `if/then` block required.

The pattern matches the precedent already in this spec:
`health_check.period_seconds.exclusiveMinimum.$data = "1/timeout_seconds"`.

## Render logic in the deployment template

The k8s deployment manifest (currently rendering both request and limit from the same capability) must use the new fields with a jq `// fallback`:

```bash
CPU_REQ=$(echo "$CONTEXT" | jq -r '.scope.capabilities.cpu_millicores')
CPU_LIM=$(echo "$CONTEXT" | jq -r '.scope.capabilities.cpu_millicores_limit // .scope.capabilities.cpu_millicores')

RAM_REQ=$(echo "$CONTEXT" | jq -r '.scope.capabilities.ram_memory')
RAM_LIM=$(echo "$CONTEXT" | jq -r '.scope.capabilities.ram_memory_limit // .scope.capabilities.ram_memory')
```

`// .scope.capabilities.cpu_millicores` evaluates to the request value when the limit is `null` or missing, giving the exact retrocompat the ticket asks for.

The implementation plan will locate the exact file(s) under `k8s/deployment/` that render `resources:` and apply this change.

## Backwards compatibility

| Scenario | Behavior |
|---|---|
| Existing scope, no new properties in DB | jq fallback ⇒ limit = request ⇒ identical manifest to today |
| New scope, user does not touch limits | Defaults are `null` ⇒ same as above |
| New scope, user picks a higher limit | Manifest renders the explicit limit; schema validates `limit ≥ request` |
| User tries `limit < request` | JSON schema rejects via `$data` minimum before the workflow runs |

No data migration needed.

## Testing plan (high-level)

- **BATS unit tests** for the deployment script: cover the four matrix cells (limit set / limit null, for both CPU and RAM), asserting the rendered `resources:` block.
- **JSON schema validation tests** (if a test harness exists for the spec): assert that `limit < request` is rejected and `limit >= request` is accepted, including the `null` case.
- **Manual smoke** in a dev environment after the implementation lands.

The testing detail belongs to the implementation plan (writing-plans), not this design doc.

## Open questions

- Exact deployment template file location and templating engine (gomplate vs helm vs raw bash + jq) — to be confirmed at implementation time. The render logic above is engine-agnostic in spirit but the syntax will be adapted.

## Out of scope / follow-ups

- Docsite documentation (under `~/nullplatform/apps/docsite/`) — separate ticket if Spin needs it user-facing.
- Symmetric treatment for other resource dimensions (ephemeral storage, GPUs) — not requested.
