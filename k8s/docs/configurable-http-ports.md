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

`Service.targetPort` stays `80` because that is the sidecar's port, not the app's.

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
