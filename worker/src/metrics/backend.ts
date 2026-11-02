/**
 * Where metrics come from: Prometheus, over the organization's metrics provider or a fixed
 * URL, or Datadog, over its API with the keys the environment or the provider holds. An
 * image picks one (METRICS_BACKEND); the telemetry routes know only this port.
 */

import type { Context, Payload } from "@nullplatform/plugin";
import { metricList, type MetricDescriptor } from "./catalog";
import { readMetric, type MetricAnswer, type MetricPorts } from "./data";
import { DATADOG_METRICS, readDatadogMetric, type DatadogPorts } from "./datadog";

export interface MetricsBackend {
  /** What metric:list advertises. */
  list(): { results: MetricDescriptor[] };
  /** One metric:data, from the notification's arguments and, for a trace query, the notification itself. */
  read(args: Record<string, unknown> | undefined, payload: Payload, context: Context, signal?: AbortSignal): Promise<MetricAnswer>;
}

const PROVIDER_CACHE_MS = 5 * 60_000;
const providerUrls = new Map<string, { at: number; url: string }>();

/**
 * Where Prometheus is for `scopeId`: the fixed URL when the image gives one, else the
 * organization's metrics provider at the scope's NRN, as `np provider list --categories metrics`
 * finds it, remembered for five minutes per scope.
 */
export async function prometheusUrlOf(context: Context, fixed: string | undefined, scopeId: string): Promise<string> {
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

/** Prometheus over `prometheus`, at the fixed URL or the provider's. */
export const prometheusBackend = (prometheus: MetricPorts["prometheus"], fixedUrl?: string): MetricsBackend => ({
  list: metricList,
  read: (args, payload, context, signal) => readMetric({ prometheus, prometheusUrl: (scopeId) => prometheusUrlOf(context, fixedUrl, scopeId) }, args, signal),
});

export const datadogBackend = (ports: DatadogPorts): MetricsBackend => ({
  list: () => ({ results: DATADOG_METRICS }),
  read: (args, payload, context, signal) => readDatadogMetric(ports, args, payload, context, signal),
});
