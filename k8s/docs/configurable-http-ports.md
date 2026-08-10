# Configurable HTTP Ports

The k8s scope supports configuring the port on which the application's main HTTP listener binds, and exposing additional HTTP ports as siblings of the main listener.

## Capabilities

### `main_http_port`

- **Type:** integer
- **Default:** `8080`
- **Range:** 1024 – 65535
- **Required:** yes (with default — the form pre-fills 8080)

The port your application binds to inside the container. When set, the following are derived from it automatically:

| Resource | Field | Value |
|---|---|---|
| `Deployment` (application container) | `containerPort` | `main_http_port` |
| `Deployment` (application container) | livenessProbe / readinessProbe / startupProbe port | `main_http_port` |
| `Deployment` (http traffic-manager sidecar) | `UPSTREAM_PORT` env | `main_http_port` |
| `Deployment` (http traffic-manager sidecar) | TCP probe `app_port` | `main_http_port` |
| `Service` | `port` (cluster-public) | `main_http_port` |
| `Ingress` (initial and blue-green) | backend service port | `main_http_port` |
| Istio `Service` and `HTTPRoute` | port | `main_http_port` |
| `Service` | `targetPort` | `main_traffic_manager_port` (NOT `main_http_port`) |

`Service.targetPort` is the sidecar's port, not the app's — it tracks
`main_traffic_manager_port` (default `80`), not `main_http_port`. See
[Moving the sidecar off port 80](#moving-the-sidecar-off-port-80).

### `main_traffic_manager_port`

- **Type:** integer
- **Default:** `80`
- **Valid values:** `80`, or `1024`–`65535`
- **Configured via:** `container-orchestration` provider at
  `.cluster.main_traffic_manager_port`, the `scope-configurations` provider at
  `.deployment.main_traffic_manager_port`, or the `MAIN_TRAFFIC_MANAGER_PORT`
  env var in `values.yaml`. Precedence follows the usual order —
  `scope-configurations`, then `container-orchestration`, then env, then default.

The port the main traffic-manager sidecar binds inside the pod. It sets the
sidecar's `containerPort`, its `LISTENER_PORT` env var, all three of its probes,
and `Service.targetPort` on the main Service and on the Istio and ARO routes.

#### Moving the sidecar off port 80

Port 80 is privileged, and hardened clusters routinely do not allow pod-to-pod
traffic on it. When that happens the symptom is deceptive: the pod reports
`Ready` and requests time out. Kubelet probes are node-local and never leave the
ENI, so they reach the sidecar while cross-node traffic from the gateway is
dropped.

The diagnostic is a three-way comparison against the same `podIP:80`:

```bash
POD_IP=$(kubectl -n nullplatform get pod -l deployment_id=<id> -o jsonpath='{.items[0].status.podIP}')
NODE=$(kubectl -n nullplatform get pod -l deployment_id=<id> -o jsonpath='{.items[0].spec.nodeName}')

kubectl -n gateways exec deploy/gateway-private-istio -- \
  curl -s -m 5 -o /dev/null -w "cross-node 80 -> %{http_code}\n" "http://$POD_IP:80/"
kubectl debug node/$NODE -it --image=curlimages/curl -- \
  curl -s -m 5 -o /dev/null -w "same-node 80 -> %{http_code}\n" "http://$POD_IP:80/"
```

Same-node succeeding while cross-node times out means the filter is at the
network layer, not in the manifest. With AWS VPC CNI, pod IPs are real VPC IPs,
so cross-node pod-to-pod traffic is evaluated by security groups. Under custom
networking (pods on a secondary CIDR) the relevant security group is the one in
the `ENIConfig` CRD, not the node's:

```bash
kubectl get eniconfig -A -o custom-columns=NAME:.metadata.name,SUBNET:.spec.subnet,SG:.spec.securityGroups
```

To adopt a different port, in this order:

1. Allow the port (`10080` recommended) inbound on the security group attached
   to the pod ENIs.
2. Set `main_traffic_manager_port` in the `container-orchestration` provider.
3. Deploy.

The order matters. Setting the knob before opening the port yields a green
deployment that receives no traffic, so blue/green never promotes — blue keeps
serving, so it stalls rather than breaking.

`10080` is the recommended value because it is `80 + 10000`, the same offset
`additional_ports` sidecars already use, and it is clear of Istio's
`15000`–`15090` range and of common application defaults.

Do not work around the filtering by pointing `Service.targetPort` at the
application port. That takes nginx out of the request path — losing
`client_max_body_size 75M`, graceful shutdown, and request metrics — and the
next deployment re-renders `targetPort` from the template, so the change does
not survive.

### `additional_ports[].type = "HTTP"`

`additional_ports` is a list of extra ports the scope exposes alongside the main HTTP listener. Each item has:

- `port`: integer 1024–65535
- `type`: `"GRPC"` or `"HTTP"`

For each additional port (HTTP or GRPC), the deployment generates a traffic-manager sidecar that handles external traffic. The sidecar is **always** in the request path: it adds nginx-level metrics, graceful-shutdown handling, and body-size limits.

The architecture differs slightly between HTTP and GRPC because of how the application is expected to bind ports:

### HTTP additional port — same model as `main_http_port`

The application **binds the additional port directly** (e.g., `app.listen(9090)`), exactly the way it binds `main_http_port`. The sidecar bindes a different *internal* port, `port + 10000`, to avoid colliding with the application. K8s `Service` exposes `port` externally and routes to the sidecar's internal port; the sidecar then proxies to the application on `port`.

For example, with `main_http_port=8081` and `additional_port: {port: 9090, type: HTTP}`:

```
External client
    │ http://service:9090
    ▼
K8s Service "d-{scope}-{deploy}-http-9090"   port: 9090, targetPort: 19090
    │
    ▼
Sidecar container "http-9090"   listens on 19090  →  proxies to localhost:9090
    │
    ▼
Application container   binds 9090 (and also 8081 for the main listener)
```

The application sees two real listeners: `8081` (main) and `9090` (additional). External traffic to either flows through its respective sidecar (the main `http` sidecar for `8081`, the `http-9090` sidecar for `9090`).

**Constraint:** because the sidecar uses `port + 10000`, the additional port must be `≤ 55535` for HTTP. Above that the offset overflows the 65535 max TCP port.

### GRPC additional port — sidecar terminates protocol

The application does **NOT** bind GRPC additional ports. The `grpc-{port}` sidecar binds `{port}` directly and translates gRPC into HTTP, proxying to `localhost:main_http_port`. The application speaks only HTTP on `main_http_port` and serves both main HTTP traffic and any incoming gRPC requests (received already translated to HTTP).

### Summary

| | HTTP additional port | GRPC additional port |
|---|---|---|
| App binds the port | yes, directly | no (sidecar binds it) |
| Sidecar internal port | `port + 10000` | `port` |
| Service `port` (external) | `port` | `port` |
| Service `targetPort` | `port + 10000` (sidecar) | `port` (sidecar) |
| Sidecar `UPSTREAM_PORT` | `port` (the app's same port) | `main_http_port` (default in image) |
| Protocol translation | none | gRPC → HTTP |
| Max valid `port` | 55535 | 65535 |

## ALB capacity and listener lifecycle

### Each additional port opens its own ALB listener

The Ingress generated for each additional port (HTTP or GRPC) declares `alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":{port}}]'`. This means **every additional port translates into a dedicated listener on the shared ALB** (`spec.ports[].port == {scope additional port}`). The main scope ingress keeps its standard `[{"HTTP":80},{"HTTPS":443}]` listener pair.

Concrete example for an ALB shared by three scopes, each with `main_http_port=8081` plus one HTTP additional port `9090`, `9091`, and `9092` respectively:

| ALB listener | Source ingress | Backend |
|---|---|---|
| `:80` | All scopes (main) | Main sidecar `http` |
| `:443` | All scopes (main) | Main sidecar `http` |
| `:9090` | scope A `http-9090` ingress | Sidecar `http-9090` of scope A |
| `:9091` | scope B `http-9091` ingress | Sidecar `http-9091` of scope B |
| `:9092` | scope C `http-9092` ingress | Sidecar `http-9092` of scope C |

The main listeners (80/443) are shared across all scopes via the IngressGroup; one listener serves many ingress rules (one per scope host). Additional ports are NOT shared by default — each port is a separate listener.

### AWS limit: 50 listeners per ALB

This is an AWS hard quota. With many scopes using additional ports on the same ALB, the listener count climbs quickly: each scope adds 1 listener per HTTP/GRPC additional port. A pre-flight check in `k8s/deployment/validate_alb_target_group_capacity` rejects deployments when the ALB would exceed `ALB_MAX_LISTENERS` (default `48`, leaves 2 slots of headroom before the AWS limit). The threshold is configurable in `values.yaml` or via the `scope-configurations`/`container-orchestration` provider.

If a deployment fails with `❌ ALB 'NAME' has reached listener capacity: X/48`, the operator options are:
- Reduce `additional_ports` across the scopes sharing the ALB
- Increase `ALB_MAX_LISTENERS` (only safe up to 49 — at 50 the next deploy will hit the AWS quota itself)
- Request an AWS service-quota increase for listeners per ALB (the limit is technically adjustable, although AWS tends to deny large increases)
- Move some scopes to a separate ALB (the recommended path)

### Listeners are cleaned up automatically

Operators do not need to manage ALB listeners by hand. The AWS Load Balancer Controller owns listener lifecycle through the IngressGroup mechanism:

- When the **first** Ingress with `alb.ingress.kubernetes.io/listen-ports` referencing a given port is created, the controller adds that listener to the shared ALB.
- When the **last** Ingress referencing that port is deleted, the controller removes the listener.
- In between, multiple Ingresses on the same port coexist as different rules on a single listener; the controller never duplicates the listener itself.

This means deleting a deployment (which deletes its Ingresses) is sufficient to reclaim listener capacity — no manual cleanup of the ALB is required. If a scope is the only consumer of a particular additional port across the ALB, deleting that scope returns the listener to the pool and frees an `ALB_MAX_LISTENERS` slot for the next deployment.

## Backward Compatibility

- Existing scopes that do not set `main_http_port` get `8080` automatically via the JSON Schema default and the `// 8080` jq fallback in `build_context`. No migration is required.
- The `traffic-manager` image's `start.sh` defaults `UPSTREAM_PORT` to `8080` when the env is not provided, so an upgraded image with un-upgraded scope templates continues to behave like the old image.
- Adding `HTTP` to the `additional_ports.type` enum is strictly additive — existing entries with `"GRPC"` remain valid.

## Implementation Map

- JSON Schema and UI Schema: `k8s/specs/service-spec.json.tpl`
- Build context extraction: `k8s/deployment/build_context` (look for `MAIN_HTTP_PORT`)
- Templates that consume `main_http_port`: `k8s/deployment/templates/{service,deployment,initial-ingress,blue-green-ingress}.yaml.tpl` and `k8s/deployment/templates/istio/*.tpl`
- HTTP additional_ports sidecar: `k8s/deployment/templates/deployment.yaml.tpl` (look for `else if eq .type "HTTP"`)
- traffic-manager image: `nullplatform/k8s-tools/traffic-manager` — `UPSTREAM_PORT` env handled in `start.sh`

## Tests

- `k8s/deployment/tests/build_context.bats` covers `main_http_port` extraction with present, absent, and `null` cases, and verifies the `tonumber` cast.
- `k8s/deployment/tests/ingress_template_shape.bats` verifies the per-port HTTPS listener annotation on each ingress branch and pins the absence of `ssl-redirect` on additional-port ingresses.
- `k8s/deployment/tests/verify_ingress_reconciliation.bats` covers the weight-dedupe behavior introduced because a shared ALB listener used to surface multiple matching rules (the multi-rule scenario is no longer reachable now that each additional port has its own listener, but the dedupe is kept defensively).
- `k8s/deployment/tests/validate_alb_target_group_capacity.bats` covers both target-group capacity and the listener-capacity validation (`ALB_MAX_LISTENERS`).
