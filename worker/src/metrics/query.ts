/**
 * The PromQL and the window of a metric:data: the port of build_filters, build_query and the
 * time handling of k8s/metric/metric. Arguments arrive as the bash exported them: every key
 * uppercased, arrays joined by commas.
 */

import { ActionError } from "@nullplatform/plugin";
import { isHttpMetric } from "./catalog";

export interface MetricArguments {
  metric: string;
  applicationId: string;
  scopeId: string;
  deploymentId: string;
  /** Comma-joined labels, "" for none. */
  groupBy: string;
  /** ISO strings, "" when absent. */
  startTime: string;
  endTime: string;
  /** Seconds, as text; "" when absent. */
  period: string;
  timeRange: string;
  interval: string;
}

/** An argument as the bash exported it: arrays joined by commas, anything else as text. */
export function exported(value: unknown): string {
  if (value === null || value === undefined) {
    return "";
  }
  return Array.isArray(value) ? value.map((item) => (item === null || item === undefined ? "" : String(item))).join(",") : String(value);
}

export function metricArguments(raw: Record<string, unknown> | undefined): MetricArguments {
  const args = raw ?? {};
  const metric = exported(args.metric) || exported(args.metric_name);
  if (metric === "") {
    throw new ActionError("MISSING_METRIC", "metric is required");
  }
  const applicationId = exported(args.application_id);
  if (applicationId === "") {
    throw new ActionError("MISSING_APPLICATION_ID", "application_id is required");
  }
  const groupBy = exported(args.group_by);
  return {
    metric,
    applicationId,
    scopeId: exported(args.scope_id),
    deploymentId: exported(args.deployment_id),
    groupBy: groupBy === "[]" ? "" : groupBy,
    startTime: exported(args.start_time),
    endTime: exported(args.end_time),
    period: exported(args.period),
    timeRange: exported(args.time_range),
    interval: exported(args.interval),
  };
}

/** The label matchers of every query: the application, and the scope and deployment when given. */
export function buildFilters(args: Pick<MetricArguments, "applicationId" | "scopeId" | "deploymentId">): string {
  const parts: string[] = [];
  if (args.applicationId) parts.push(`application_id="${args.applicationId}"`);
  if (args.scopeId) parts.push(`scope_id="${args.scopeId}"`);
  if (args.deploymentId && args.deploymentId !== "null") parts.push(`deployment_id="${args.deploymentId}"`);
  return parts.join(",");
}

const COUNT = "nullplatform_http_response_time_count";
const OK = 'quality="OK (2XX, 3XX)"';

/** The PromQL of `metric`, as the bash built it, `up{…}` for a metric it did not know. */
export function buildQuery(metric: string, filters: string, interval: string, groupBy: string, scopeId: string): string {
  const by = groupBy ? ` by (${groupBy})` : "";
  const rate = (f: string) => `sum(rate(${COUNT}{${f}}[${interval}]))${by}`;
  const avg = (series: string) => `avg(${series}{${filters}})${by}`;
  const job = `job-${scopeId}-.*`;
  const relabel = (expr: string) => `label_replace(${expr}, "scope_id", "$1", "job_name", "job-([0-9]+)-.*")`;
  switch (metric) {
    case "http.healthcheck_count":
      return rate(`${filters},is_healthcheck="yes"`);
    case "http.healthcheck_fail":
      return `${rate(`${filters},is_healthcheck="yes"`)} - ${rate(`${filters},is_healthcheck="yes",${OK}`)}`;
    case "system.cpu_usage_percentage_by_instance":
      return `avg(nullplatform_system_cpu_usage_percentage{${filters}}) by (instance_id)`;
    case "system.memory_usage_percentage":
      return avg("nullplatform_system_memory_usage_percentage");
    case "system.cpu_usage_percentage":
      return avg("nullplatform_system_cpu_usage_percentage");
    case "system.used_memory_kb":
      return avg("nullplatform_system_used_memory_kb");
    case "http.response_time":
      return `sum(idelta(nullplatform_http_response_time{${filters}}[${interval}]))${by}/sum(idelta(${COUNT}{${filters}}[${interval}]))${by}`;
    case "http.rpm":
      return `${rate(filters)} * 60`;
    case "http.error_rate":
      return `((${rate(filters)} * 60 - ${rate(`${filters},${OK}`)} * 60) / (${rate(filters)} * 60 )) *100`;
    case "cronjob.execution_count":
      return `sum by (scope_id) (${relabel(`increase(kube_job_status_succeeded{job_name=~"${job}"}[${interval}]) +increase(kube_job_status_failed{job_name=~"${job}"}[${interval}])`)})`;
    case "cronjob.success_count":
      return `sum by (scope_id) (${relabel(`increase(kube_job_status_succeeded{job_name=~"${job}"}[${interval}])`)})`;
    case "cronjob.failure_count":
      return `sum by (scope_id) (${relabel(`increase(kube_job_status_failed{job_name=~"${job}"}[${interval}])`)})`;
    case "cronjob.cpu_usage":
      return `avg(avg_over_time(container_cpu_usage_seconds_total{pod=~"${job}", container!="", container!="POD"}[${interval}])) * 100`;
    case "cronjob.memory_usage":
      return `avg by (scope_id) (label_replace(container_memory_usage_bytes{pod=~"${job}", container!="", container!="POD"} / on(pod, container) kube_pod_container_resource_limits{resource="memory", unit="byte", pod=~"${job}"}, "scope_id", "$1", "pod", "job-([0-9]+)-.*")) * 100`;
    default:
      return `up{${filters}}`;
  }
}

export interface Window {
  /** Unix seconds. */
  start: number;
  end: number;
  /** Seconds between points. */
  step: number;
  /** The range of the rate functions, e.g. "5m". */
  interval: string;
}

/** An ISO time as the bash parsed it: the fraction dropped, invalid is 0. */
function isoSeconds(value: string): number {
  const parsed = Date.parse(value.replace(/\.\d+Z$/, "Z"));
  return Number.isNaN(parsed) ? 0 : Math.floor(parsed / 1000);
}

function durationSeconds(value: string, fallback: number): number {
  const match = /^(\d+)([hmsd])$/.exec(value);
  if (!match) {
    return fallback;
  }
  const amount = Number(match[1]);
  return { h: 3600, m: 60, s: 1, d: 86400 }[match[2] as "h" | "m" | "s" | "d"]! * amount;
}

/**
 * The window a metric:data covers. With a start and an end: the step is the period (60 by
 * default) and the rate range is period/60 minutes, at least 1, at least 5 for the HTTP metrics.
 * Otherwise the window ends now and reaches back time_range (1h by default), stepping by interval.
 */
export function timeWindow(args: Pick<MetricArguments, "metric" | "startTime" | "endTime" | "period" | "timeRange" | "interval">, nowMs = Date.now()): Window {
  if (args.startTime && args.endTime) {
    const period = Number(args.period);
    const step = args.period && Number.isFinite(period) ? period : 60;
    let interval = "5m";
    if (args.period && period > 0) {
      let minutes = Math.max(Math.floor(period / 60), 1);
      if (isHttpMetric(args.metric)) {
        minutes = Math.max(minutes, 5);
      }
      interval = `${minutes}m`;
    }
    return { start: isoSeconds(args.startTime), end: isoSeconds(args.endTime), step, interval };
  }
  const now = Math.floor(nowMs / 1000);
  const range = durationSeconds(args.timeRange, 3600);
  const step = /^\d+$/.test(args.interval) ? Number(args.interval) : durationSeconds(args.interval, 60);
  return { start: now - range, end: now, step, interval: args.interval || "5m" };
}
