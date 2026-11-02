import { main } from "@nullplatform/plugin";
import { kubeClient } from "./kube/client";
import { prometheusClient } from "./metrics/prometheus";
import { scopeWorker } from "./worker";

// The image's own configuration, read here and nowhere else; a blank variable gives none.
//   NP_PACKAGE_NAME, NP_PACKAGE_VERSION   what the image is to the agent (the pin's package)
//   NP_SCOPE_ENTRYPOINT, NP_SERVICE_PATH  the bash entrypoint and the scope folder it runs
//   NP_OVERRIDES_PATH                     the overlays laid over it, comma-separated
//   NP_AGENT_SOURCES                      the notification sources routed here
//   K8S_SCOPE_PROVIDER                    the id(s) of the Kubernetes scope's specification, comma-separated, for the channel
//   NAMESPACE_OVERRIDE (or K8S_NAMESPACE) the namespace the scope's pods live in; unset reads every namespace by label
//   PROMETHEUS_URL                        a fixed Prometheus; unset asks the organization's metrics provider
//   KUBECONFIG, KUBE_CONTEXT              read by @kubernetes/client-node; unset, the in-cluster service account
const env = process.env;
const list = (value: string | undefined): string[] => (value ?? "").split(",").map((item) => item.trim()).filter(Boolean);

const plugin = scopeWorker(
  {
    package: { name: env.NP_PACKAGE_NAME || "scopes-worker", version: env.NP_PACKAGE_VERSION || "0.0.0" },
    sources: env.NP_AGENT_SOURCES ? list(env.NP_AGENT_SOURCES) : ["service", "telemetry"],
    entrypoint: { path: env.NP_SCOPE_ENTRYPOINT || "/app/pkg/entrypoint", servicePath: env.NP_SERVICE_PATH || "/app/pkg/k8s", overridesPaths: list(env.NP_OVERRIDES_PATH) },
    scopeProviders: list(env.K8S_SCOPE_PROVIDER),
    namespace: env.NAMESPACE_OVERRIDE || env.K8S_NAMESPACE || undefined,
  },
  { kube: kubeClient({ context: env.KUBE_CONTEXT || undefined }), prometheus: prometheusClient(), prometheusUrl: env.PROMETHEUS_URL || undefined },
);

await main(plugin);
