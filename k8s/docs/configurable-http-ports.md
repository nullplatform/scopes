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

For `HTTP` ports, the deployment generates:

- A `containerPort: {port}` declaration on the application container — **the application is expected to bind this port directly**. No sidecar is involved.
- A `Service` named `d-{scope_id}-{deployment_id}-http-{port}` with `targetPort: {port}` that routes external traffic to the application's port.
- An `Ingress` for the additional HTTP listener.

For `GRPC` ports, the existing gRPC sidecar pattern is unchanged: a `grpc-{port}` traffic-manager sidecar terminates gRPC on `{port}` and proxies HTTP to the application's `main_http_port`. The application does NOT bind gRPC additional ports — the sidecar does — which is why the protocol distinction matters.

| | HTTP additional port | GRPC additional port |
|---|---|---|
| App binds the port | yes | no (sidecar binds it) |
| Sidecar created | no | yes (`grpc-{port}` traffic-manager) |
| Service `targetPort` | `{port}` (the app) | `{port}` (the sidecar) |
| Protocol translation | none | gRPC → HTTP to app on `main_http_port` |

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
