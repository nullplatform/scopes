# ALB Autocreation

The k8s scope can provision new Application Load Balancers (ALBs) on demand when the declared pool of ALBs is exhausted. The behavior is opt-in and only triggers during scope creation; existing scopes are never moved to autocreated ALBs automatically.

## When the autocreate path runs

The flow only triggers when **all** of the following are true:

- `ALB_AUTOCREATE_ENABLED=true` in `values.yaml` or in the `container-orchestration` provider.
- `DNS_TYPE=route53` (autocreation requires the same load-balancing path used by Route53 scopes).
- Every candidate ALB in the pool (base + additional balancers declared in the provider) reports a rule count `>= ALB_MAX_CAPACITY`.
- The scope being created does not already have a Route53 record (a scope being recreated reuses its existing ALB and does not trigger autocreation).

If any candidate is below the threshold, the scope creation uses that candidate and the autocreate path is not taken.

## Configuration

| Key | Default | Description |
|---|---|---|
| `ALB_AUTOCREATE_ENABLED` | `false` | Master switch. When `false`, behavior is identical to previous releases. |
| `ALB_AUTOCREATE_NAME_PREFIX` | `nullplatform-auto-` | Prefix for autocreated ALB names. Final name format: `<prefix><public|private>-<6 hex chars>`. Must match `^[a-z0-9-]+$` and be ≤18 chars so the rendered name stays under the AWS 32-char ALB name limit. |
| `ALB_AUTOCREATE_TIMEOUT_SECONDS` | `300` | How long `wait_for_alb` polls AWS for the new ALB to reach `state=active` before failing the scope creation. The AWS Load Balancer Controller usually takes 2–4 minutes. Must be a positive integer. |

All three keys are also readable from `providers.container-orchestration.balancer.{autocreate_enabled, autocreate_name_prefix, autocreate_timeout_seconds}`.

## How it works

1. `resolve_balancer` evaluates the candidate pool — the base ALB plus the `additional_public_names` / `additional_private_names` list declared in the `container-orchestration` provider — and picks the least-loaded one.
2. If that candidate's rule count is at or above `ALB_MAX_CAPACITY` and `ALB_AUTOCREATE_ENABLED=true`, `resolve_balancer` sources `autocreate_alb`.
3. `autocreate_alb` generates a unique ALB name (`<prefix><public|private>-<6 hex>`) and **patches the container-orchestration provider via `np provider patch`** to append the new name to `additional_public_names` or `additional_private_names` (visibility-dependent). The provider is the authoritative registry of ALBs the platform uses.
4. `autocreate_alb` renders `scope/templates/ingress-dummy.yaml.tpl` into `$OUTPUT_DIR/ingress-dummy-<alb-name>.yaml`. The dummy Ingress carries `alb.ingress.kubernetes.io/group.name=<new-name>` and `alb.ingress.kubernetes.io/load-balancer-name=<new-name>`, which is what makes the AWS Load Balancer Controller materialize the ALB once the file is applied.
5. The workflow step `apply autocreated ingress` (in `k8s/scope/workflows/create.yaml`) applies whatever templates are in `$OUTPUT_DIR` via the standard `apply_templates` script. Its `post: wait for alb` runs `wait_for_alb`, which polls `aws elbv2 describe-load-balancers` every 10 seconds until the ALB reports `State.Code=active` (or `failed`/timeout, in which case the scope creation fails). An info-level heartbeat is emitted every ~30s so the operator can see progress.
6. Once active, `wait_for_alb` tags the ALB with `nullplatform:managed-by=autocreate`, `nullplatform:visibility=internet-facing|internal`, and `nullplatform:created-by-scope-id=<scope-id>`. **These tags are audit metadata only**, surfacing the lineage of which scope provisioned which ALB. Discovery does NOT depend on these tags.
7. The rest of the scope creation proceeds with `ALB_NAME` set to the new ALB.

## How concurrent scope creations behave

When scope A triggers autocreate, the provider is patched **before** the ALB is active. Scope B that starts during this window reads the provider list, sees the new ALB name, and treats it as a normal candidate. AWS will return `LoadBalancerNotFound` for the in-flight ALB during the few seconds before it shows up in the API; `resolve_balancer` interprets that error specifically as "0 rules" so the in-flight ALB wins least-loaded selection in scope B and no second autocreate fires. Scope B then waits on the same ALB via its own `wait_for_alb` step.

## Required permissions

In addition to the permissions already required for capacity validation, the autocreate path needs:

**Nullplatform API credentials.** The script calls `np provider list` and `np provider patch`, so the workflow environment must provide either `NP_TOKEN` or `NULLPLATFORM_API_KEY` with write access to the container-orchestration provider for the relevant NRN. Without these, the patch step fails with `❌ Failed to patch container-orchestration provider with new ALB`.

**AWS IAM (agent role).**

- `elasticloadbalancing:AddTags` — for the audit tags `wait_for_alb` applies once the ALB is active. Failure here is non-fatal (logged as a warning, the scope creation proceeds).

No new Kubernetes permissions are needed beyond those the agent already has for scope resources.

## Operational notes

- Scope creations that trigger autocreation are slower (typically 2–4 minutes extra). This is the expected behavior, not a regression. The platform logs `🔧 Best candidate ALB '...' is at or above capacity (X/Y); triggering autocreate` when it happens, followed by `⏳ Still waiting for ALB '...' to become active (provisioning, ~30s elapsed)` heartbeats while the controller provisions.
- The dummy Ingress (`nullplatform-autocreate-<alb-name>`) is created in the scope's namespace. It exposes no real traffic — the rule points to a fixed `404` response via the standard `alb.ingress.kubernetes.io/actions.response-404` annotation — and exists only to keep the ALB alive in the eyes of the AWS Load Balancer Controller. Deleting the dummy Ingress will cause the controller to delete the ALB.
- The ALB is registered in the nullplatform provider (not in the customer's IaC). Two consequences:
  1. The provider becomes the source of truth for the ALB pool; subsequent scope creations read it directly.
  2. The cloud's IaC (Terraform, OpenTofu, CloudFormation) is **not** updated automatically. If your IaC is the source of truth for ALB inventory, you should reconcile autocreated ALBs into it through your own process.

## Failure modes

| Failure | Outcome |
|---|---|
| `ALB_AUTOCREATE_NAME_PREFIX` invalid (bad charset or >18 chars) | Scope creation exits 1 with the validation error before any AWS or provider call. |
| `np provider list` cannot find a container-orchestration provider for the NRN | Scope creation exits 1 with `❌ No container-orchestration provider found for NRN '<nrn>'`. |
| `np provider patch` fails (no API token / no write access) | Scope creation exits 1 with `❌ Failed to patch container-orchestration provider with new ALB` + hint about `NP_TOKEN` / `NULLPLATFORM_API_KEY`. |
| `gomplate` render of the dummy Ingress fails | Scope creation exits 1 with `❌ Failed to render ingress-dummy template`. |
| ALB never reaches `active` within `ALB_AUTOCREATE_TIMEOUT_SECONDS` | Scope creation exits 1; check controller logs and AWS quota for ALBs in the region. |
| AWS reports the ALB state as `failed` | Scope creation exits 1 immediately. |
| `AddTags` call fails (no IAM permission) | Logged as `⚠️  Could not tag ALB '<name>' (audit only — provider registration already succeeded)`. The scope creation continues; the tags are documentation only. |

## What is out of scope

- Migration of existing scopes to autocreated ALBs. Use the `Recreate scope` action if needed.
- Automatic cleanup of unused autocreated ALBs (no scopes referencing them).
- Updating the cloud IaC (Terraform / OpenTofu / CloudFormation) with the new ALB.
