/**
 * The telemetry actions, answered on the cluster and the metrics backend: one
 * raw route per action (log:read, metric:list, metric:data, instance:data),
 * each matched by its action. The code behind them is the k8s-telemetry
 * worker's, as it ran beside the scope, and the Datadog overlay's metrics
 * ported beside it; here they run inside the scope's own image, no bash.
 */

import { where, type Context, type Payload, type Route } from "@nullplatform/plugin";
import { listInstances } from "./instances/list";
import type { KubeClient } from "./kube/client";
import { readLogs } from "./logs/read";
import type { MetricsBackend } from "./metrics/backend";
import instanceDataSample from "./samples/instance-data.json" with { type: "json" };
import logReadSample from "./samples/log-read.json" with { type: "json" };
import metricDataSample from "./samples/metric-data.json" with { type: "json" };
import metricListSample from "./samples/metric-list.json" with { type: "json" };

export interface TelemetryConfig {
  /** The ids of the Kubernetes scope's specification in this organization, what the channel matches; none leaves the channel to the installation. */
  scopeProviders: string[];
  /** The namespace the scope's pods live in; undefined selects them by label across every namespace. */
  namespace?: string;
}

export interface TelemetryPorts {
  kube: KubeClient;
  metrics: MetricsBackend;
}

const argumentsOf = (payload: Payload): Record<string, unknown> | undefined => (payload.arguments && typeof payload.arguments === "object" ? (payload.arguments as Record<string, unknown>) : undefined);

/** The four routes, in the order the agent channel lists them. */
export function telemetryRoutes(config: TelemetryConfig, ports: TelemetryPorts): Route[] {
  const channel = config.scopeProviders.length > 0 ? { source: "telemetry", filter: { "arguments.scope_provider": { $in: config.scopeProviders } } } : undefined;
  const logs = { kube: ports.kube, namespace: config.namespace };
  const route = (action: string, sample: Payload, handler: (payload: Payload, context: Context) => Promise<unknown>): Route => ({
    name: action,
    match: where({ action }),
    output: () => "raw" as const,
    ...(channel ? { channel } : {}),
    sample,
    handler,
  });
  return [
    route("log:read", logReadSample.notification, (payload, context) => readLogs(logs, argumentsOf(payload), context.signal)),
    route("metric:list", metricListSample.notification, async () => ports.metrics.list()),
    route("metric:data", metricDataSample.notification, (payload, context) => ports.metrics.read(argumentsOf(payload), payload, context, context.signal)),
    route("instance:data", instanceDataSample.notification, (payload, context) => listInstances(logs, argumentsOf(payload), context.signal)),
  ];
}
