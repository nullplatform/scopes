/**
 * metric:data: the window, the query, one Prometheus call, and the answer as the bash shaped
 * it: `{ metric, type, period_in_seconds, unit, results: [{ selector, data: [{ timestamp, value }] }] }`.
 * A point whose value is not a number is left out: the telemetry API refuses null values.
 */

import { ActionError } from "@nullplatform/plugin";
import { metricConfig } from "./catalog";
import type { PrometheusClient, PrometheusRangeResponse } from "./prometheus";
import { buildFilters, buildQuery, metricArguments, timeWindow } from "./query";

export interface MetricPorts {
  prometheus: PrometheusClient;
  /** Where Prometheus is for this scope: a fixed URL, or the organization's metrics provider. */
  prometheusUrl: (scopeId: string, signal?: AbortSignal) => Promise<string>;
}

export interface MetricPoint {
  timestamp: string;
  value: number;
}

export interface MetricAnswer {
  metric: string;
  type: string;
  period_in_seconds: number;
  unit: string;
  results: Array<{ selector: Record<string, string>; data: MetricPoint[] }>;
}

/** Unix seconds as jq's todate prints them. */
export const todate = (seconds: number): string => new Date(seconds * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");

export function transformResponse(response: PrometheusRangeResponse): MetricAnswer["results"] {
  if (response.status !== "success" || !response.data?.result?.length) {
    return [];
  }
  return response.data.result.map((series) => ({
    selector: series.metric,
    data: series.values.flatMap(([at, value]) => {
      const number = Number(value);
      return Number.isFinite(number) ? [{ timestamp: todate(Number(at)), value: number }] : [];
    }),
  }));
}

export async function readMetric(ports: MetricPorts, raw: Record<string, unknown> | undefined, signal?: AbortSignal, nowMs = Date.now()): Promise<MetricAnswer> {
  const args = metricArguments(raw);
  const url = await ports.prometheusUrl(args.scopeId, signal);
  if (!url) {
    throw new ActionError("NO_PROMETHEUS", "There is no prometheus provider configured. Please configure prometheus in Platform settings and try again.");
  }
  const window = timeWindow(args, nowMs);
  const query = buildQuery(args.metric, buildFilters(args), window.interval, args.groupBy, args.scopeId);
  const response = await ports.prometheus.queryRange(url, query, window.start, window.end, window.step, signal);
  const { type, unit } = metricConfig(args.metric);
  return { metric: args.metric, type, period_in_seconds: window.step, unit, results: transformResponse(response) };
}
