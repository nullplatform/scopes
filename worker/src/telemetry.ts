/**
 * The telemetry actions, answered on the cluster and Prometheus: one raw route
 * per action (log:read, metric:list, metric:data, instance:data), each matched
 * by its action unless an overlay provides its workflow (overlay.ts), in which
 * case the bash route answers it. The code behind them is the k8s-telemetry
 * worker's, as it ran beside the scope; here it runs inside the scope's own
 * image.
 */

import { where, type Context, type Payload, type Route } from "@nullplatform/plugin";
import { listInstances } from "./instances/list";
import type { KubeClient } from "./kube/client";
import { readLogs } from "./logs/read";
import { metricList } from "./metrics/catalog";
import { readMetric } from "./metrics/data";
import type { PrometheusClient } from "./metrics/prometheus";
import { overlayWorkflow } from "./overlay";
import instanceDataSample from "./samples/instance-data.json" with { type: "json" };
import logReadSample from "./samples/log-read.json" with { type: "json" };
import metricDataSample from "./samples/metric-data.json" with { type: "json" };
import metricListSample from "./samples/metric-list.json" with { type: "json" };

export interface TelemetryConfig {
  /** The ids of the Kubernetes scope's specification in this organization, what the channel matches; none leaves the channel to the installation. */
  scopeProviders: string[];
  /** The namespace the scope's pods live in; undefined selects them by label across every namespace. */
  namespace?: string;
  /** The overlays laid over the scope: an action one of them has a workflow for is the bash's. */
  overridesPaths: readonly string[];
}

export interface TelemetryPorts {
  kube: KubeClient;
  prometheus: PrometheusClient;
  /** A fixed Prometheus URL; without one, the organization's metrics provider is asked through the platform API. */
  prometheusUrl?: string;
}

const PROVIDER_CACHE_MS = 5 * 60_000;
const providerUrls = new Map<string, { at: number; url: string }>();

/**
 * Where Prometheus is for `scopeId`: the fixed URL when the deployment gives one, else the
 * organization's metrics provider at the scope's NRN, as `np provider list --categories metrics`
 * finds it, remembered for five minutes per scope.
 */
async function prometheusUrlOf(context: Context, fixed: string | undefined, scopeId: string): Promise<string> {
  if (fixed) {
    return fixed;
  }
  const remembered = providerUrls.get(scopeId);
  if (remembered && Date.now() - remembered.at < PROVIDER_CACHE_MS) {
    return remembered.url;
  }
  const scope = await context.api.scope(scopeId).get<{ nrn: string }>();
  const pages = context.api.provider.list({ categories: "metrics", nrn: scope.nrn });
  const first = (await pages[Symbol.asyncIterator]().next()).value as { results?: Array<{ attributes?: { server?: { url?: string } } }> } | undefined;
  const url = first?.results?.[0]?.attributes?.server?.url ?? "";
  if (url) {
    providerUrls.set(scopeId, { at: Date.now(), url });
  }
  return url;
}

const argumentsOf = (payload: Payload): Record<string, unknown> | undefined => (payload.arguments && typeof payload.arguments === "object" ? (payload.arguments as Record<string, unknown>) : undefined);

/** The four routes, in the order the agent channel lists them. */
export function telemetryRoutes(config: TelemetryConfig, ports: TelemetryPorts): Route[] {
  const channel = config.scopeProviders.length > 0 ? { source: "telemetry", filter: { "arguments.scope_provider": { $in: config.scopeProviders } } } : undefined;
  const logs = { kube: ports.kube, namespace: config.namespace };
  const route = (action: string, sample: Payload, handler: (payload: Payload, context: Context) => Promise<unknown>): Route => ({
    name: action,
    match: (payload) => where({ action })(payload) && overlayWorkflow(action, config.overridesPaths) === undefined,
    output: () => "raw" as const,
    ...(channel ? { channel } : {}),
    sample,
    handler,
  });
  return [
    route("log:read", logReadSample.notification, (payload, context) => readLogs(logs, argumentsOf(payload), context.signal)),
    route("metric:list", metricListSample.notification, async () => metricList()),
    route("metric:data", metricDataSample.notification, (payload, context) => readMetric({ prometheus: ports.prometheus, prometheusUrl: (scopeId) => prometheusUrlOf(context, ports.prometheusUrl, scopeId) }, argumentsOf(payload), context.signal)),
    route("instance:data", instanceDataSample.notification, (payload, context) => listInstances(logs, argumentsOf(payload), context.signal)),
  ];
}
