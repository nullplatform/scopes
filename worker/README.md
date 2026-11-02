# The scopes worker

The worker the nullplatform agent dials for a scope image, on `@nullplatform/plugin` 0.3.0.
It does two things:

- **Telemetry on the cluster.** `log:read`, `metric:list`, `metric:data` and `instance:data`
  are answered here, from the Kubernetes API and Prometheus, with no bash, no `kubectl` and no
  `np` in the path: the k8s-telemetry worker's code (`src/kube`, `src/logs`, `src/metrics`,
  `src/instances`), which read a page of logs in milliseconds where the scripts took tens of
  them. An overlay that provides a workflow for one of these actions (the datadog folder's
  `metric/workflows`) keeps it: that action goes to the bash like any other (`src/overlay.ts`).
- **Everything else by the bash entrypoint.** Scope actions, deployments, parameters and the
  overlays' actions run `entrypoint --service-path=<scope> [--overrides-path=<overlay>]…` with
  `NP_ACTION_CONTEXT`, exactly as the worker-bridge ran it (`src/bash.ts`). What the entrypoint
  prints is the answer and is said line by line to the worker's log as it runs.

`docker/containers.Dockerfile` compiles it into the containers image, which the overlays build
on, so no image needs the worker-bridge base any more.

## Configuration

Read once, in `src/index.ts`, from the image's environment (the agent's worker pin may override it):

| Variable | Meaning |
|---|---|
| `NP_PACKAGE_NAME`, `NP_PACKAGE_VERSION` | What the image is to the agent: the pin's package, and its version. |
| `NP_SCOPE_ENTRYPOINT`, `NP_SERVICE_PATH` | The bash entrypoint and the scope folder it runs (`/app/pkg/entrypoint`, `/app/pkg/k8s`). |
| `NP_OVERRIDES_PATH` | The overlays laid over the scope, comma-separated (`/app/pkg/datadog`). |
| `NP_AGENT_SOURCES` | The notification sources routed here (`service,telemetry`). |
| `K8S_SCOPE_PROVIDER` | The id(s) of the Kubernetes scope's specification, for the channel the manifest describes. |
| `NAMESPACE_OVERRIDE`, `K8S_NAMESPACE` | The namespace the scope's pods live in; unset reads every namespace by label. |
| `PROMETHEUS_URL` | A fixed Prometheus; unset asks the organization's metrics provider. |
| `KUBECONFIG`, `KUBE_CONTEXT` | How the cluster is reached; unset, the in-cluster service account. |

## Develop

```bash
cd worker
bun install
bun test                 # the telemetry suites, the bash runner, the overlay rule, the routing
bunx tsc --noEmit -p .
bun run describe         # the manifest
docker build -f ../docker/containers.Dockerfile ..   # the image, from the repository root
```

The answers are the telemetry API's contract (`main-telemetry-logs-api/services/json_schemas.js`).
Behaviour follows the bash scope's scripts; a difference is deliberate: a page of logs is as full
as its window allows and at least the console's tier for that window, bounded to 320 KiB because
the platform refuses bigger answers; the window holds at the millisecond; `instance_id` takes a
comma-separated list.
