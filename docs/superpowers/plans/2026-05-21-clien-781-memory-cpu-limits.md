# CLIEN-781 — Memory & CPU Limits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional `cpu_millicores_limit` and `ram_memory_limit` capabilities to the k8s scope so the Spin client can set Kubernetes `resources.limits` independently from `resources.requests`, with safe back-compat defaults.

**Architecture:** Add two new optional properties to the k8s scope spec. Normalize them inside `build_context` (limit defaults to request when null/missing) so the deployment template stays trivial. Render the normalized values into the application container's `resources.limits` while keeping `resources.requests` bound to the original `cpu_millicores` / `ram_memory` fields.

**Tech Stack:** JSON Schema (with JSONForms uiSchema), bash + jq for context normalization, gomplate for template rendering, BATS for tests.

**Spec:** [`docs/superpowers/specs/2026-05-21-clien-781-memory-cpu-limits-design.md`](../specs/2026-05-21-clien-781-memory-cpu-limits-design.md)

---

## File Structure

**Modified files:**

- `k8s/specs/service-spec.json.tpl` — add two `properties` and update the `Categorization`/`Category` to rename "Processor" → "Resources" and add two new `Control` entries.
- `k8s/deployment/build_context` — add a `normalize_capability_limits` function that mutates `$CONTEXT` to fill `.scope.capabilities.cpu_millicores_limit` and `.scope.capabilities.ram_memory_limit` with the request value when null/missing. Call it before the final context write.
- `k8s/deployment/templates/deployment.yaml.tpl` — application container only (lines 313–319): keep `requests.cpu/memory` bound to `cpu_millicores` / `ram_memory`, change `limits.cpu/memory` to read `cpu_millicores_limit` / `ram_memory_limit`. Sidecars (lines 148–153, 201–206, 255–260) are NOT touched — they use `container_cpu_in_millicores` / `container_memory_in_memory` from a ConfigMap.

**New tests:**

- `k8s/deployment/tests/build_context.bats` — add a section for `normalize_capability_limits` covering the four matrix cells (limit set / limit null, for CPU and RAM) plus the "field absent" case.
- `k8s/deployment/tests/deployment_template_shape.bats` (new file) — grep-based structural assertions that the application container `resources` block uses the right field for request vs limit. Mirrors `tests/ingress_template_shape.bats`.

**Not modified:** sidecar resource blocks, CLI, docsite, API spec.

---

## Task 1: Add `cpu_millicores_limit` and `ram_memory_limit` properties to the JSON schema

**Files:**
- Modify: `k8s/specs/service-spec.json.tpl` (properties block, lines 485–492 area for CPU; lines 315–358 area for RAM)

There is no JSON-schema test harness in this repo, so this task has no automated test. The schema is validated implicitly by the deployment workflow and by manual `jq` sanity checks in step 2.

- [ ] **Step 1: Add the two new properties to `attributes.schema.properties`**

After the existing `cpu_millicores` property block (end at line 492), add `cpu_millicores_limit`:

```json
,
"cpu_millicores_limit":{
   "type":["integer","null"],
   "title":"CPU Millicores Limit",
   "default":null,
   "maximum":4000,
   "minimum":{
      "$data":"1/cpu_millicores"
   },
   "description":"Maximum CPU the container can use (in millicores). Leave empty to use the same value as the request."
}
```

After the existing `ram_memory` property block (end at line 358), add `ram_memory_limit`:

```json
,
"ram_memory_limit":{
   "type":["integer","null"],
   "oneOf":[
      {"const":null,  "title":"Same as request"},
      {"const":64,    "title":"64 MB"},
      {"const":128,   "title":"128 MB"},
      {"const":256,   "title":"256 MB"},
      {"const":512,   "title":"512 MB"},
      {"const":1024,  "title":"1 GB"},
      {"const":2048,  "title":"2 GB"},
      {"const":4096,  "title":"4 GB"},
      {"const":8192,  "title":"8 GB"},
      {"const":16384, "title":"16 GB"}
   ],
   "title":"RAM Memory Limit",
   "default":null,
   "minimum":{
      "$data":"1/ram_memory"
   },
   "description":"Maximum memory the container can use (in MB). Setting this higher than the request increases the chance the scheduler kills the pod under pressure."
}
```

Do NOT add either field to the top-level `required` array — both stay optional.

- [ ] **Step 2: Validate the JSON is still well-formed**

Run:
```bash
jq empty k8s/specs/service-spec.json.tpl
```
Expected: no output, exit code 0.

If gomplate is available locally, also confirm the template renders to valid JSON:
```bash
NRN="nrn:test" gomplate -f k8s/specs/service-spec.json.tpl | jq empty
```
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add k8s/specs/service-spec.json.tpl
git commit -m "feat: add cpu_millicores_limit and ram_memory_limit properties to k8s scope spec"
```

---

## Task 2: Rename "Processor" → "Resources" and add the limit Controls to the uiSchema

**Files:**
- Modify: `k8s/specs/service-spec.json.tpl` (uiSchema `Category` block, lines 46–55)

No automated test — uiSchema is rendered by the frontend. We validate by grep-based assertion in step 2 and visual smoke later.

- [ ] **Step 1: Rename the Category label and add two Controls**

Locate the `Category` whose label is `"Processor"` (line 47). Replace the whole block (lines 46–55) with:

```json
{
   "type":"Category",
   "label":"Resources",
   "elements":[
      {
         "type":"Control",
         "label":"CPU Millicores",
         "scope":"#/properties/cpu_millicores"
      },
      {
         "type":"Control",
         "label":"CPU Millicores Limit",
         "scope":"#/properties/cpu_millicores_limit"
      },
      {
         "type":"Control",
         "label":"RAM Memory Limit",
         "scope":"#/properties/ram_memory_limit"
      }
   ]
}
```

- [ ] **Step 2: Sanity-check the uiSchema is well-formed and has the expected shape**

Run:
```bash
jq -e '
  .attributes.schema.uiSchema
  | .. | objects | select(.label? == "Resources")
  | .elements | map(.scope) as $scopes
  | ($scopes | length) == 3
    and ($scopes | index("#/properties/cpu_millicores") != null)
    and ($scopes | index("#/properties/cpu_millicores_limit") != null)
    and ($scopes | index("#/properties/ram_memory_limit") != null)
' k8s/specs/service-spec.json.tpl >/dev/null && echo OK
```
Expected: `OK`.

Also confirm "Processor" is gone:
```bash
! grep -q '"Processor"' k8s/specs/service-spec.json.tpl && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add k8s/specs/service-spec.json.tpl
git commit -m "feat: rename Processor tab to Resources and surface CPU/RAM limit controls"
```

---

## Task 3: Add `normalize_capability_limits` to `build_context` (TDD)

**Files:**
- Modify: `k8s/deployment/build_context`
- Modify: `k8s/deployment/tests/build_context.bats`

This is the back-compat heart of the change. The function takes `$CONTEXT` (JSON) and fills `.scope.capabilities.cpu_millicores_limit` and `.scope.capabilities.ram_memory_limit` with the corresponding request value when the field is `null` or missing. Existing values pass through unchanged.

- [ ] **Step 1: Write failing tests in `tests/build_context.bats`**

Append at the end of `k8s/deployment/tests/build_context.bats`:

```bash
# =============================================================================
# normalize_capability_limits Function Tests (CLIEN-781)
# Fills in *_limit with the corresponding request value when null or missing,
# leaves explicit values untouched.
# =============================================================================

setup_normalize_limits_fn() {
  eval "$(sed -n '/^normalize_capability_limits()/,/^}/p' "$PROJECT_ROOT/k8s/deployment/build_context")"
}

@test "normalize_capability_limits: fills CPU limit from request when limit is absent" {
  setup_normalize_limits_fn
  local in='{"scope":{"capabilities":{"cpu_millicores":500,"ram_memory":1024,"ram_memory_limit":2048}}}'
  local out
  out=$(normalize_capability_limits "$in")
  assert_equal "$(echo "$out" | jq -r '.scope.capabilities.cpu_millicores_limit')" "500"
}

@test "normalize_capability_limits: fills RAM limit from request when limit is absent" {
  setup_normalize_limits_fn
  local in='{"scope":{"capabilities":{"cpu_millicores":500,"cpu_millicores_limit":700,"ram_memory":1024}}}'
  local out
  out=$(normalize_capability_limits "$in")
  assert_equal "$(echo "$out" | jq -r '.scope.capabilities.ram_memory_limit')" "1024"
}

@test "normalize_capability_limits: fills both limits when both are absent" {
  setup_normalize_limits_fn
  local in='{"scope":{"capabilities":{"cpu_millicores":500,"ram_memory":1024}}}'
  local out
  out=$(normalize_capability_limits "$in")
  assert_equal "$(echo "$out" | jq -r '.scope.capabilities.cpu_millicores_limit')" "500"
  assert_equal "$(echo "$out" | jq -r '.scope.capabilities.ram_memory_limit')" "1024"
}

@test "normalize_capability_limits: fills both limits when both are explicit null" {
  setup_normalize_limits_fn
  local in='{"scope":{"capabilities":{"cpu_millicores":500,"cpu_millicores_limit":null,"ram_memory":1024,"ram_memory_limit":null}}}'
  local out
  out=$(normalize_capability_limits "$in")
  assert_equal "$(echo "$out" | jq -r '.scope.capabilities.cpu_millicores_limit')" "500"
  assert_equal "$(echo "$out" | jq -r '.scope.capabilities.ram_memory_limit')" "1024"
}

@test "normalize_capability_limits: preserves explicit non-null limits" {
  setup_normalize_limits_fn
  local in='{"scope":{"capabilities":{"cpu_millicores":500,"cpu_millicores_limit":2000,"ram_memory":1024,"ram_memory_limit":4096}}}'
  local out
  out=$(normalize_capability_limits "$in")
  assert_equal "$(echo "$out" | jq -r '.scope.capabilities.cpu_millicores_limit')" "2000"
  assert_equal "$(echo "$out" | jq -r '.scope.capabilities.ram_memory_limit')" "4096"
}
```

- [ ] **Step 2: Run the new tests, confirm they fail**

Run:
```bash
bats k8s/deployment/tests/build_context.bats -f normalize_capability_limits
```
Expected: 5 failures, message about `normalize_capability_limits: command not found` (or similar — function does not exist yet).

- [ ] **Step 3: Implement `normalize_capability_limits` in `build_context`**

Open `k8s/deployment/build_context`. Above the `validate_status()` function (search for `^validate_status\(\)`), insert:

```bash
# Fill in *_limit capability fields with the corresponding request value when
# the limit is missing or explicitly null. Idempotent. CLIEN-781.
normalize_capability_limits() {
    echo "$1" | jq '
      .scope.capabilities.cpu_millicores_limit = (.scope.capabilities.cpu_millicores_limit // .scope.capabilities.cpu_millicores)
      | .scope.capabilities.ram_memory_limit  = (.scope.capabilities.ram_memory_limit  // .scope.capabilities.ram_memory)
    '
}
```

Then wire it into the final context assembly. Find the block ending at line 314 (the big `jq '. + { ... }')` invocation around lines 285–314 that produces the final `$CONTEXT`). Immediately after that block (i.e., right before the `DEPLOYMENT_ID=$(echo "$CONTEXT" | jq -r '.deployment.id')` line at 316), add:

```bash
CONTEXT=$(normalize_capability_limits "$CONTEXT")
```

- [ ] **Step 4: Run the new tests, confirm they pass**

Run:
```bash
bats k8s/deployment/tests/build_context.bats -f normalize_capability_limits
```
Expected: 5 tests pass.

- [ ] **Step 5: Run the full build_context test suite to ensure no regressions**

Run:
```bash
bats k8s/deployment/tests/build_context.bats
```
Expected: all tests pass (baseline of this file is currently green per the existing CI; we are only adding tests).

- [ ] **Step 6: Commit**

```bash
git add k8s/deployment/build_context k8s/deployment/tests/build_context.bats
git commit -m "feat: normalize cpu/ram limit capabilities to request value when unset"
```

---

## Task 4: Render limits from normalized fields in the application container (TDD via template-shape test)

**Files:**
- Create: `k8s/deployment/tests/deployment_template_shape.bats`
- Modify: `k8s/deployment/templates/deployment.yaml.tpl` (lines 313–319 only — the application container, NOT the sidecars)

We assert the template shape with grep (same approach as `ingress_template_shape.bats`). End-to-end rendering through gomplate is exercised by the existing build pipeline; the shape test catches regressions like accidentally rebinding `limits.cpu` back to `cpu_millicores`.

- [ ] **Step 1: Write the failing template-shape test**

Create `k8s/deployment/tests/deployment_template_shape.bats`:

```bash
#!/usr/bin/env bats
# =============================================================================
# Structural tests for the deployment template.
# Verifies the application container's resources block uses the right
# capability for request vs limit. CLIEN-781.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/deployment.yaml.tpl"
}

# Slice the file from "name: application" to the next container header,
# isolating the application container's block from the sidecars (which keep
# using container_cpu_in_millicores / container_memory_in_memory).
app_container_block() {
  awk '
    /^[[:space:]]+- name: application[[:space:]]*$/ { in_app=1 }
    in_app { print }
    /^[[:space:]]+terminationMessagePolicy:/ && in_app { exit }
  ' "$TEMPLATE"
}

@test "deployment template: application container limits.cpu uses cpu_millicores_limit" {
  block=$(app_container_block)
  echo "$block" | grep -E 'cpu:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.cpu_millicores_limit[[:space:]]*\}\}m' >/dev/null
}

@test "deployment template: application container limits.memory uses ram_memory_limit" {
  block=$(app_container_block)
  echo "$block" | grep -E 'memory:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.ram_memory_limit[[:space:]]*\}\}Mi' >/dev/null
}

@test "deployment template: application container requests.cpu still uses cpu_millicores" {
  block=$(app_container_block)
  echo "$block" | grep -E 'cpu:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.cpu_millicores[[:space:]]*\}\}m' >/dev/null
}

@test "deployment template: application container requests.memory still uses ram_memory" {
  block=$(app_container_block)
  echo "$block" | grep -E 'memory:[[:space:]]*\{\{[[:space:]]*\.scope\.capabilities\.ram_memory[[:space:]]*\}\}Mi' >/dev/null
}

@test "deployment template: sidecars still use container_cpu_in_millicores / container_memory_in_memory" {
  # Sidecars are everything BEFORE the application container block.
  before=$(awk '/^[[:space:]]+- name: application[[:space:]]*$/ {exit} {print}' "$TEMPLATE")
  echo "$before" | grep -F '{{ .container_cpu_in_millicores }}m' >/dev/null
  echo "$before" | grep -F '{{ .container_memory_in_memory }}Mi' >/dev/null
  # And sidecars must NOT have been switched to the new fields.
  ! echo "$before" | grep -F 'cpu_millicores_limit' >/dev/null
  ! echo "$before" | grep -F 'ram_memory_limit' >/dev/null
}
```

- [ ] **Step 2: Run the new tests, confirm they fail**

Run:
```bash
bats k8s/deployment/tests/deployment_template_shape.bats
```
Expected: at least the first two tests fail (limits.cpu / limits.memory still pointing at `cpu_millicores` / `ram_memory` — request fields).

- [ ] **Step 3: Edit the application container's resource block**

Open `k8s/deployment/templates/deployment.yaml.tpl`. Locate lines 313–319 (the `- name: application` container's `resources` block). Replace those exact lines with:

```yaml
          resources:
            limits:
              cpu: {{ .scope.capabilities.cpu_millicores_limit }}m
              memory: {{ .scope.capabilities.ram_memory_limit }}Mi
            requests:
              cpu: {{ .scope.capabilities.cpu_millicores }}m
              memory: {{ .scope.capabilities.ram_memory }}Mi
```

Do NOT touch the sidecar `resources:` blocks at lines 148–153, 201–206, or 255–260.

- [ ] **Step 4: Run the template-shape tests, confirm they pass**

Run:
```bash
bats k8s/deployment/tests/deployment_template_shape.bats
```
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add k8s/deployment/templates/deployment.yaml.tpl k8s/deployment/tests/deployment_template_shape.bats
git commit -m "feat: render application container limits from normalized capability fields"
```

---

## Task 5: End-to-end smoke (manual)

This is a sanity check, not a test — the project has no automated gomplate-render harness for `deployment.yaml.tpl`. Skip if `gomplate` is not installed locally.

- [ ] **Step 1: Render the deployment template with a sample CONTEXT and inspect the output**

```bash
cat > /tmp/clien781_ctx.json <<'JSON'
{
  "scope": {
    "id": "scope-test",
    "capabilities": {
      "cpu_millicores": 500,
      "cpu_millicores_limit": 1000,
      "ram_memory": 1024,
      "ram_memory_limit": 2048,
      "health_check": {"enabled": true, "type": "HTTP", "path": "/health", "initial_delay_seconds": 10},
      "additional_ports": []
    }
  },
  "deployment": {"id": "deploy-test"},
  "asset": {"url": "example.com/app:1.0"},
  "container_cpu_in_millicores": "93",
  "container_memory_in_memory": "64",
  "main_http_port": 8080,
  "traffic_image": "example.com/traffic:1.0",
  "blue_replicas": "0",
  "green_replicas": "1",
  "total_replicas": "1",
  "blue_deployment_id": "",
  "pull_secrets": [],
  "pdb_enabled": "false",
  "pdb_max_unavailable": "1",
  "service_account_name": "default",
  "traffic_manager_config_map": "tm-config",
  "blue_additional_port_services": {}
}
JSON

gomplate -c .=/tmp/clien781_ctx.json -f k8s/deployment/templates/deployment.yaml.tpl \
  | grep -A4 'name: application' \
  | grep -A3 'resources:' \
  | sed -n '1,8p'
```

Expected output should include:
```
          resources:
            limits:
              cpu: 1000m
              memory: 2048Mi
            requests:
              cpu: 500m
              memory: 1024Mi
```

- [ ] **Step 2: Render again with the limit fields omitted (back-compat case)**

Edit `/tmp/clien781_ctx.json` and remove `cpu_millicores_limit` and `ram_memory_limit`. Then re-run the same `gomplate ... | grep` chain.

**Wait** — gomplate will error on missing keys. This step illustrates that the back-compat path MUST go through `build_context` (which normalizes), not raw template rendering. The build pipeline always runs `build_context` first, so in production this is fine. The manual smoke here just confirms that the normalized context produces the right output; the "missing keys" path is covered by the BATS tests in Task 3.

- [ ] **Step 3: Clean up**

```bash
rm /tmp/clien781_ctx.json
```

---

## Task 6: Run the full k8s test suite and push the branch

- [ ] **Step 1: Run all k8s BATS tests in batches** (per the project memory rule about avoiding BATS temp-dir collisions)

Run:
```bash
bats k8s/deployment/tests/build_context.bats
bats k8s/deployment/tests/build_deployment.bats
bats k8s/deployment/tests/deployment_template_shape.bats
bats k8s/deployment/tests/ingress_template_shape.bats
bats k8s/deployment/tests/apply_templates.bats
```
Expected: all green.

- [ ] **Step 2: Confirm git status is clean and on the right branch**

Run:
```bash
git status
git log --oneline beta..HEAD
```
Expected: clean tree; four feature commits (Tasks 1–4) on top of beta.

- [ ] **Step 3: Push the branch**

Run:
```bash
git push -u origin feature/clien-781-memory-cpu-limits
```

- [ ] **Step 4: Run the quality-gate skill before opening a PR**

Per the user's global `CLAUDE.md`, run `quality-gate` after non-trivial coding tasks and before claiming work is done. The skill orchestrates code-review, security audit, and simplification checks.

---

## Out of scope (for follow-up tickets)

- Docsite documentation for the new capabilities.
- CLI / OpenAPI changes — none required, the capability schema is consumed dynamically.
- Symmetric treatment for other resource dimensions (ephemeral storage, GPUs).
- Sidecar resource overrides — sidecars keep using `container_cpu_in_millicores` / `container_memory_in_memory` from the ConfigMap.

---

## Self-review checklist (done by plan author)

- [x] **Spec coverage:** every section of the spec (schema, uiSchema, render, back-compat, validation, testing) maps to a task.
- [x] **No placeholders:** every step has concrete code, paths, and expected output.
- [x] **Type consistency:** `normalize_capability_limits` is referenced consistently; field names match the schema (`cpu_millicores_limit`, `ram_memory_limit`).
- [x] **Scope:** single coherent change, one branch, one PR.
