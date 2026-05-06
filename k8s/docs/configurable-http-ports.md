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

For both `HTTP` and `GRPC` additional ports, the deployment generates:

- A traffic-manager sidecar that binds the additional port externally and proxies traffic to the application on its `main_http_port`. The container is named `http-{port}` for HTTP and `grpc-{port}` for GRPC.
- A `Service` named `d-{scope_id}-{deployment_id}-{http|grpc}-{port}` with `targetPort: {port}` that routes external traffic to the sidecar.
- An `Ingress` for the additional listener.

**Important contract:** the application **must NOT bind additional ports** itself. The application binds only `main_http_port`. The sidecar at `{port}` proxies all traffic to `localhost:main_http_port`, where the application serves requests. This is identical to the existing gRPC pattern, just extended to HTTP.

The sidecar is not a no-op pass-through — it provides nginx-level metrics, graceful-shutdown handling, body-size limits, and protocol translation (for gRPC). Removing it would lose those features.

| | HTTP additional port | GRPC additional port |
|---|---|---|
| App binds the port | no (sidecar binds it) | no (sidecar binds it) |
| Sidecar created | yes (`http-{port}` traffic-manager) | yes (`grpc-{port}` traffic-manager) |
| Service `targetPort` | `{port}` (the sidecar) | `{port}` (the sidecar) |
| Sidecar `UPSTREAM_PORT` | `main_http_port` | `main_http_port` (default in image) |
| Protocol translation | none (HTTP→HTTP) | gRPC → HTTP |

If your application code currently binds an additional port directly (e.g., `app.listen(9090)`), remove that listener — nullplatform's sidecar handles the external binding. Your app will receive requests for the additional port on its `main_http_port` listener.

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
