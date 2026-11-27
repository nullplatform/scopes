# Service-to-service traffic

A k8s scope on the Istio HTTPRoute templates can get a stable in-cluster name that other workloads call on the ports the application serves (HTTP, WebSocket and gRPC):

```
http://{app}-{scope}.{k8s namespace}.svc.cluster.local:{main_http_port}
```

Calls go through an Istio gateway and follow the same blue-green weights as the scope's public or private route. No sidecars, VirtualServices or DestinationRules. Off by default; with it off the scope renders exactly what it did before.

## How it works

| Object | Name | What it does |
|---|---|---|
| `Service` (`type: ExternalName`) | `names.stable_service` | Resolves to the gateway's Service, `<gateway>-istio.<gateway namespace>.svc.<cluster domain>` |
| `HTTPRoute`, one per HTTP or GRPC port | `<stable service>-http-<port>`, `<stable service>-grpc-<port>` | Attached to listener `<listener_prefix><port>` of the gateway; same backends and weights as the scope's route |

- Ports: `main_http_port` plus every `additional_ports` entry of type `HTTP` or `GRPC`. WebSocket (`protocol: web_sockets`) upgrades on the main port pass through the HTTP route.
- GRPC ports use an `HTTPRoute` too (gRPC is HTTP/2; no method matching is needed, and cleanup and verification stay on one kind). Their per-deployment Service port gets `name: grpc-<port>` and `appProtocol: grpc` so the gateway speaks HTTP/2 to the pods, and the stable Service names the port `grpc-<port>`.
- ExternalName does not remap ports: the gateway needs a listener for every port of the scope. The deployment fails naming the missing ones.
- The objects carry `nullplatform.io/stable-service: "true"` and the scope labels, but no `deployment_id`, so they live as long as the scope's route: created by the initial deployment, updated by switch traffic, finalize and rollback, deleted with it.
- The internal routes end in `-http-<port>` so the naming engine never mistakes them for the scope's main HTTPRoute.

## Modes

Chosen per cluster, must match how the gateway was installed (`gateway.inCluster` in the base chart, `gateway_in_cluster_*` in the base tofu module).

| | `shared` (default) | `dedicated` |
|---|---|---|
| Gateway | The scope's private gateway | `gateway-in-cluster` |
| Hostnames | `<svc>.<ns>.svc.<cluster domain>` | Also `<svc>.<ns>` |

In `shared` mode the gateway's in-cluster listeners only accept `*.svc.<cluster domain>`, so the scope's real domains are never served over plain HTTP on the private load balancer.

The bare `<svc>` is not a hostname in either mode, so clients in the same namespace must call `<svc>.<ns>` or the FQDN. All namespaces share the gateway's listeners and the HTTP `Host` carries no namespace: two namespaces with the same `<svc>` would both claim Host `<svc>`, and the oldest route would silently get the other's traffic.

## Configuration

`scope-configurations` provider, `networking.service_to_service.*`; falls back to `gateway.service_to_service.*` in the container-orchestration provider.

To enable it per account, namespace or dimension, set **Networking → Service-to-service → Enabled** (and **Mode**) in a scope-configurations provider. Its schema is `k8s/specs/scope-configuration.json.tpl` (see [the k8s README](../README.md#the-scope-configurations-schema)). Cluster-wide, set `SERVICE_TO_SERVICE_ENABLED` on the agent instead.

| Property | Env var | Default |
|---|---|---|
| `enabled` (`"true"`/`"false"` like the other on/off keys; a JSON boolean also works via API) | `SERVICE_TO_SERVICE_ENABLED` | `false` |
| `mode` | `SERVICE_TO_SERVICE_MODE` | `shared` |
| `gateway_name` | - | `shared`: the private gateway name; `dedicated`: `gateway-in-cluster` |
| `listener_prefix` | - | `in-cluster-` |
| `cluster_domain` | - | `cluster.local` |
| `name_pattern` | - | `{.application.slug}-{.scope.slug}` |

The gateway namespace is the scope's `gateway_namespace`. `name_pattern` uses the [resource naming](resource-naming.md) engine with a 63-character budget and no id appended; once created, the name is kept even if the pattern changes.

## Failures

| Condition | Result |
|---|---|
| ALB ingress templates or `GATEWAY_TYPE=aro_cluster` | Deployment fails in build context |
| A port is 443 or an Istio port (15000-15090) | Deployment fails in build context |
| Gateway missing, or no listener for a port | Deployment fails before applying, listing what is missing |
| A Service with the stable name exists and is not this scope's | Deployment fails; nothing is overwritten |
| Disabled after being enabled, or a port removed | The next deployment deletes the objects no longer rendered |
| Deployment deleted | Its objects are deleted, whether the feature is on or off |
| GRPC port of a deployment created before the feature was on (its Service has no `appProtocol: grpc`) | gRPC calls to that deployment fail with `protocol error` until a newer deployment replaces it |

The agent needs `get` on `gateways` in the gateway namespace and `get`/`list`/`delete` on `services` and `httproutes` in the scope's namespace.

## Limits

- No access control between workloads: any pod in the cluster can call any scope's stable name, as with a plain k8s Service. In `shared` mode the in-cluster routes are also reachable from the VPC through the private load balancer if its security group opens the ports. Restricting callers (e.g. an Istio `AuthorizationPolicy` on the gateway) is out of scope for this version.
