/**
 * Metrics from Datadog: the port of datadog/metric/{build_context,list,metric}, the overlay
 * the containers-datadog image carried. The same seven metrics the Prometheus side lists
 * (titles and one entry differ, as the overlay's did), each a Datadog query over the
 * `nullplatform.scope.*` series the sidecar reports, asked of the timeseries API and shaped
 * into the telemetry API's answer. The keys come from the environment, else from the
 * organization's metrics provider at the scope's NRN.
 */

import { ActionError, type Context } from "@nullplatform/plugin";
import type { MetricDescriptor } from "./catalog";
import { todate, type MetricAnswer } from "./data";
import { exported, metricArguments, type MetricArguments } from "./query";

const FILTERS = ["scope_id", "instance_id"];

export const DATADOG_METRICS: MetricDescriptor[] = [
  { name: "http.rpm", title: "Throughput", unit: "rpm", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "http.response_time", title: "Response time", unit: "ms", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "http.error_rate", title: "Error rate", unit: "%", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "system.cpu_usage_percentage", title: "CPU usage", unit: "%", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "system.memory_usage_percentage", title: "Memory usage", unit: "%", available_filters: FILTERS, available_group_by: ["scope_id", "instance_id"] },
  { name: "http.healthcheck_count", title: "Healthcheck", unit: "check", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "http.healthcheck_fail", title: "Healthcheck failures", unit: "count", available_filters: FILTERS, available_group_by: ["instance_id"] },
];

const UNITS: Record<string, string> = {
  "http.error_rate": "percent",
  "http.response_time": "seconds",
  "http.rpm": "count_per_minute",
  "http.healthcheck_count": "count",
  "http.healthcheck_fail": "count",
  "trace.http.request.p99": "milliseconds",
  "system.cpu_usage_percentage": "percent",
  "system.memory_usage_percentage": "percent",
  "system.used_memory_kb": "kilobytes",
};

/** Every metric is a gauge; the unit is the overlay's, `unknown` for a metric it did not know. */
export const datadogConfig = (name: string): { type: "gauge"; unit: string } => ({ type: "gauge", unit: UNITS[name] ?? "unknown" });

/** The tag filters of every query: the application, and the scope and deployment when given. */
export function datadogFilters(args: Pick<MetricArguments, "applicationId" | "scopeId" | "deploymentId">): string {
  const parts: string[] = [];
  if (args.applicationId) {
    parts.push(`application_id:${args.applicationId}`);
  }
  if (args.scopeId) {
    parts.push(`scope_id:${args.scopeId}`);
  }
  if (args.deploymentId && args.deploymentId !== "null") {
    parts.push(`deployment_id:${args.deploymentId}`);
  }
  return parts.join(",");
}

/** What a trace query names its service and environment by, read from the notification as the overlay did. */
export interface TraceTarget {
  environment: string;
  /** The repository's last path segment, as `basename` cut it. */
  repositoryName: string;
}

export interface DatadogWindow {
  /** Unix seconds. */
  start: number;
  end: number;
  /** The rollup step, in seconds: the period, else 30 for a span of six minutes or less, else 60. */
  step: number;
}

const REQUESTS = "nullplatform.scope.request_count";

/** The Datadog query of `metric`, as the overlay built it, `avg:<metric>{…}` for a metric it did not know. */
export function datadogQuery(metric: string, filters: string, window: DatadogWindow, groupBy: string, trace: TraceTarget): string {
  const by = groupBy ? ` by {${groupBy.split(",").map((label) => label.trim()).filter(Boolean).join(",")}}` : "";
  const sum = (series: string, tags: string, rollup = 60): string => `sum:${series}{${tags}}${by}.rollup(sum, ${rollup})`;
  const traceService = `service:${trace.repositoryName}-kubernetes,env:${trace.environment}`;
  const span = window.end - window.start;
  switch (metric) {
    case "http.healthcheck_count":
      return `sum:${REQUESTS}{${filters},is_healthcheck:yes} by {instance_id}.rollup(sum, ${window.step})`;
    case "http.healthcheck_fail":
      return `sum:${REQUESTS}{${filters},is_healthcheck:yes} by {instance_id}.rollup(sum, ${window.step}) - sum:${REQUESTS}{${filters},is_healthcheck:yes,quality:ok_2xx_3xx} by {instance_id}.rollup(sum, ${window.step})`;
    case "system.memory_usage_percentage":
      return `avg:nullplatform.scope.memory_usage_percentage{${filters}}${by}`;
    case "system.cpu_usage_percentage":
      return `avg:nullplatform.scope.cpu_usage_percentage{${filters}}${by}`;
    case "system.used_memory_kb":
      return `avg:nullplatform.scope.memory_usage_kb{${filters}}${by}`;
    case "http.response_time":
      return `${sum("nullplatform.scope.response_time", filters)} / ${sum(REQUESTS, filters)}`;
    case "http.rpm":
      return sum(REQUESTS, filters);
    case "http.error_rate":
      return `((${sum(REQUESTS, filters)} - ${sum(REQUESTS, `${filters},quality:ok_2xx_3xx`)}) / ${sum(REQUESTS, filters)}) * 100`;
    case "trace.http.request.p99":
      return `p99:trace.http.request{${traceService}}.rollup(avg, ${span}) * 1000`;
    default:
      if (/^p\d\d:/.test(metric)) {
        return `${metric}{${traceService}}.rollup(avg, ${span}) * 1000`;
      }
      return `avg:${metric}{${filters}}${by}`;
  }
}

/** An ISO time as the overlay parsed it: the fraction dropped, invalid is 0. */
const isoSeconds = (value: string): number => {
  const parsed = Date.parse(value.replace(/\.\d+Z$/, "Z"));
  return Number.isNaN(parsed) ? 0 : Math.floor(parsed / 1000);
};

const rangeSeconds = (value: string): number => {
  const match = /^(\d+)([hmd])$/.exec(value);
  return match ? Number(match[1]) * { h: 3600, m: 60, d: 86400 }[match[2] as "h" | "m" | "d"]! : 3600;
};

/** The window: the span given, else time_range back from now (1h by default); the step the period, else 30 s for six minutes or less, else 60. */
export function datadogWindow(args: Pick<MetricArguments, "startTime" | "endTime" | "period" | "timeRange">, nowMs = Date.now()): DatadogWindow {
  const end = args.startTime && args.endTime ? isoSeconds(args.endTime) : Math.floor(nowMs / 1000);
  const start = args.startTime && args.endTime ? isoSeconds(args.startTime) : end - rangeSeconds(args.timeRange);
  const period = Number(args.period);
  const step = args.period && Number.isFinite(period) ? period : end - start <= 360 ? 30 : 60;
  return { start, end, step };
}

export interface DatadogKeys {
  apiKey: string;
  appKey: string;
  site: string;
}

export interface DatadogSeries {
  group_tags?: string[] | Record<string, string>;
  scope?: string | Record<string, string>;
}

export interface DatadogResponse {
  errors?: unknown;
  data?: { attributes?: { series?: DatadogSeries[]; times?: number[]; values?: Array<Array<number | null>> } };
}

const tagsOf = (series: DatadogSeries): Record<string, string> => {
  const pairs = (list: string[]): Record<string, string> => Object.fromEntries(list.filter(Boolean).map((tag) => tag.split(":")).map(([key, ...rest]) => [key, rest.join(":")]));
  if (series.group_tags !== undefined) {
    return Array.isArray(series.group_tags) ? pairs(series.group_tags) : series.group_tags;
  }
  if (series.scope !== undefined) {
    return typeof series.scope === "string" ? pairs(series.scope.split(",")) : series.scope;
  }
  return {};
};

/** The answer's results: one per series, its tags the selector, a point per time with the series' value there, 0 where Datadog has none, as the overlay shaped it. */
export function transformDatadog(response: DatadogResponse): MetricAnswer["results"] {
  if (response.errors || !response.data?.attributes?.series?.length) {
    return [];
  }
  const { series, times = [], values = [] } = response.data.attributes;
  return series.map((entry, index) => ({
    selector: tagsOf(entry),
    data: values.length > 0 && times.length > 0 ? times.map((at, point) => ({ timestamp: todate(at / 1000), value: values[index]?.[point] ?? 0 })) : [],
  }));
}

/** The body the timeseries API takes for one query over the window, at one-minute points. */
export const timeseriesRequest = (query: string, window: DatadogWindow) => ({ data: { type: "timeseries_request", attributes: { formulas: [{ formula: "a" }], queries: [{ name: "a", query, data_source: "metrics" }], from: window.start * 1000, to: window.end * 1000, interval: 60_000 } } });

export interface DatadogPorts {
  fetch: typeof fetch;
  /** The keys for `scopeId`: the environment's, else the organization's metrics provider's. */
  keys: (context: Context, scopeId: string) => Promise<DatadogKeys>;
}

const KEYS_CACHE_MS = 5 * 60_000;
const remembered = new Map<string, { at: number; keys: DatadogKeys }>();

/** The keys as the overlay found them: DATADOG_API_KEY, DATADOG_APP_KEY and DATADOG_SITE, else the metrics provider's `credentials` and `settings.site`, remembered five minutes per scope. */
export function datadogKeysOf(env: Record<string, string | undefined>): DatadogPorts["keys"] {
  return async (context, scopeId) => {
    if (env.DATADOG_API_KEY && env.DATADOG_APP_KEY) {
      return { apiKey: env.DATADOG_API_KEY, appKey: env.DATADOG_APP_KEY, site: env.DATADOG_SITE || "datadoghq.com" };
    }
    const known = remembered.get(scopeId);
    if (known && Date.now() - known.at < KEYS_CACHE_MS) {
      return known.keys;
    }
    const scope = await context.api.scope(scopeId).get<{ nrn: string }>();
    const pages = context.api.provider.list({ categories: "metrics", nrn: scope.nrn });
    const first = (await pages[Symbol.asyncIterator]().next()).value as { results?: Array<{ attributes?: { credentials?: { api_key?: string; app_key?: string }; settings?: { site?: string } } }> } | undefined;
    const attributes = first?.results?.[0]?.attributes ?? {};
    const keys = { apiKey: env.DATADOG_API_KEY || attributes.credentials?.api_key || "", appKey: env.DATADOG_APP_KEY || attributes.credentials?.app_key || "", site: env.DATADOG_SITE || attributes.settings?.site || "datadoghq.com" };
    if (!keys.apiKey) {
      throw new ActionError("NO_DATADOG", "There is no Datadog provider configured. Please configure Datadog in Platform settings and try again.");
    }
    if (!keys.appKey) {
      throw new ActionError("NO_DATADOG_APP_KEY", "Datadog App Key is required. Please configure App Key in Platform settings and try again.");
    }
    remembered.set(scopeId, { at: Date.now(), keys });
    return keys;
  };
}

/** The trace target the overlay read from the notification: the service's environment dimension and the repository's name. */
export function traceTargetOf(payload: Record<string, unknown>): TraceTarget {
  const service = payload.service as { dimensions?: { environment?: unknown } } | undefined;
  const tags = payload.tags as { repository_url?: unknown } | undefined;
  const url = exported(tags?.repository_url);
  return { environment: exported(service?.dimensions?.environment), repositoryName: url.replace(/\/+$/, "").split("/").pop() ?? "" };
}

export async function readDatadogMetric(ports: DatadogPorts, raw: Record<string, unknown> | undefined, payload: Record<string, unknown>, context: Context, signal?: AbortSignal, nowMs = Date.now()): Promise<MetricAnswer> {
  const args = metricArguments(raw);
  const keys = await ports.keys(context, args.scopeId);
  const window = datadogWindow(args, nowMs);
  const query = datadogQuery(args.metric, datadogFilters(args), window, args.groupBy, traceTargetOf(payload));
  const signals = [AbortSignal.timeout(20_000), ...(signal ? [signal] : [])];
  const response = await ports.fetch(`https://api.${keys.site}/api/v2/query/timeseries`, {
    method: "POST",
    headers: { "DD-API-KEY": keys.apiKey, "DD-APPLICATION-KEY": keys.appKey, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(timeseriesRequest(query, window)),
    signal: signals.length === 1 ? signals[0] : AbortSignal.any(signals),
  });
  const body = (await response.json().catch(() => ({ errors: ["not json"] }))) as DatadogResponse;
  const { type, unit } = datadogConfig(args.metric);
  return { metric: args.metric, type, period_in_seconds: window.step, unit, results: transformDatadog(body) };
}
