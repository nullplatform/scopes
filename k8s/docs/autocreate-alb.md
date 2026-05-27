# ALB Autocreation

The k8s scope can provision new Application Load Balancers (ALBs) on demand when the declared pool of ALBs is exhausted. The behavior is opt-in and only triggers during scope creation; existing scopes are never moved to autocreated ALBs automatically.

## When the autocreate path runs

The flow only triggers when **all** of the following are true:

- `ALB_AUTOCREATE_ENABLED=true` in `values.yaml` or in the `container-orchestration` provider.
- `DNS_TYPE=route53` (autocreation requires the same load-balancing path used by Route53 scopes).
- Every candidate ALB in the pool (declared base + additional balancers + previously autocreated ALBs discovered by tag) reports a rule count `>= ALB_MAX_CAPACITY`.
- The scope being created does not already have a Route53 record (a scope being recreated reuses its existing ALB and does not trigger autocreation).

If any candidate is below the threshold, the scope creation uses that candidate and the autocreate path is not taken.

## Configuration

| Key | Default | Description |
|---|---|---|
| `ALB_AUTOCREATE_ENABLED` | `false` | Master switch. When `false`, behavior is identical to previous releases. |
| `ALB_AUTOCREATE_NAME_PREFIX` | `nullplatform-auto-` | Prefix for autocreated ALB names. Final name format: `<prefix><public|private>-<6 hex chars>`. Total length must stay below the AWS 32-character ALB name limit. |
| `ALB_AUTOCREATE_TIMEOUT_SECONDS` | `300` | How long the script polls AWS for the new ALB to reach `state=active` before failing the scope creation. The AWS Load Balancer Controller usually takes 2–4 minutes. |

All three keys are also readable from `providers.container-orchestration.balancer.{autocreate_enabled, autocreate_name_prefix, autocreate_timeout_seconds}`.

## How it works

1. `resolve_balancer` evaluates the candidate pool (declared + tag-discovered ALBs) and picks the least-loaded one as today.
2. If that candidate's rule count is at or above `ALB_MAX_CAPACITY` and `ALB_AUTOCREATE_ENABLED=true`, `resolve_balancer` sources `autocreate_alb`.
3. `autocreate_alb` generates a unique ALB name, renders `scope/templates/ingress-dummy.yaml.tpl`, and applies it. The AWS Load Balancer Controller picks up the Ingress and provisions the ALB.
4. The script polls `aws elbv2 describe-load-balancers` every 10 seconds until the ALB reports `State.Code=active` (or `failed`/timeout, in which case the scope creation fails).
5. Once active, the script tags the ALB with:
   - `nullplatform:managed-by=autocreate`
   - `nullplatform:visibility=internet-facing|internal`
   - `nullplatform:created-by-scope-id=<scope-id>`
6. `resolve_balancer` substitutes the new ALB name and the rest of the scope creation proceeds.

## Discovery of previously autocreated ALBs

Every scope creation queries `resourcegroupstaggingapi:get-resources` for ALBs tagged `nullplatform:managed-by=autocreate` matching the scope's visibility. Discovered ALBs are merged into the candidate pool without any provider configuration change, so a single autocreated ALB serves many subsequent scopes before another autocreation is needed.

Discovery runs regardless of `ALB_AUTOCREATE_ENABLED`: even if the flag is later turned off, previously autocreated ALBs remain usable.

## Required AWS permissions

In addition to the permissions already required for capacity validation, the agent role needs:

- `elasticloadbalancing:AddTags` — to tag the new ALB so discovery can find it.
- `elasticloadbalancing:DescribeTags` — for the discovery path (covered by capacity validation in most agents, listed here for completeness).
- `tag:GetResources` — for the `resourcegroupstaggingapi` call used by discovery.

The dummy Ingress requires no new K8s permissions beyond those the agent already has for scope resources.

## Operational notes

- Scope creations that trigger autocreation are slower (typically 2–4 minutes extra). This is the expected behavior, not a regression. The platform logs `🔧 All candidate ALBs are at or above capacity (...); triggering autocreate` when it happens.
- The dummy Ingress (`nullplatform-autocreate-<alb-name>`) is created in the scope's namespace. It exposes no traffic and exists only to keep the ALB alive. Deleting it manually will cause the AWS Load Balancer Controller to delete the ALB.
- The ALB is registered through AWS tags rather than through the nullplatform provider configuration. Two consequences:
  1. The nullplatform provider object does not need to be updated by the script; this avoids requiring API credentials inside the scope workflow.
  2. The cloud's IaC (Terraform, OpenTofu, CloudFormation) is **not** updated automatically. If your IaC is the source of truth for ALB inventory, you should reconcile autocreated ALBs into it through your own process.

## Failure modes

| Failure | Outcome |
|---|---|
| Dummy Ingress template render fails | Scope creation exits 1 with `Failed to render ingress-dummy template`. |
| `kubectl apply` fails | Scope creation exits 1 with `Failed to apply ingress-dummy` and prints the namespace check hint. |
| ALB never reaches `active` within `ALB_AUTOCREATE_TIMEOUT_SECONDS` | Scope creation exits 1; check controller logs and AWS quota for ALBs in the region. |
| AWS reports the ALB state as `failed` | Scope creation exits 1 immediately. |
| `AddTags` call fails (no IAM permission) | Logged as `⚠️  Could not tag ALB; subsequent discovery may not find it`. The scope creation continues; the next creation will not find this ALB by tag and may autocreate another one. |

## What is out of scope

- Migration of existing scopes to autocreated ALBs. Use the `Recreate scope` action if needed.
- Automatic cleanup of unused autocreated ALBs (no scopes referencing them).
- Updating the cloud IaC (Terraform / OpenTofu / CloudFormation) with the new ALB.
