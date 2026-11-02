import { describe, expect, test } from "bun:test";
import { metricConfig, metricList } from "../src/metrics/catalog";
import { readMetric, todate, transformResponse } from "../src/metrics/data";
import { inMemoryPrometheus } from "../src/metrics/prometheus";
import { buildFilters, buildQuery, metricArguments, timeWindow } from "../src/metrics/query";
import { sampleSeries } from "./sample";

describe("catalog", () => {
  test("lists the seven metrics the bash advertised, each with filters and group-bys", () => {
    const { results } = metricList();
    expect(results.map((m) => m.name)).toEqual(["http.rpm", "http.response_time", "http.error_rate", "system.cpu_usage_percentage", "system.memory_usage_percentage", "system.used_memory_kb", "http.healthcheck_count"]);
    expect(results.every((m) => m.unit && m.available_filters.length && m.available_group_by.length)).toBe(true);
    expect(metricConfig("http.rpm")).toEqual({ type: "gauge", unit: "count_per_minute" });
    expect(metricConfig("nope")).toEqual({ type: "gauge", unit: "unknown" });
  });
});

describe("arguments and filters", () => {
  test("arrays are comma-joined as the bash exported them, [] group_by is none, metric is required", () => {
    const args = metricArguments({ metric: ["http.rpm"], application_id: 4, scope_id: "5", group_by: [], period: 60, start_time: "2026-10-20T12:00:00.000Z", end_time: "2026-10-20T13:00:00.000Z" });
    expect(args).toMatchObject({ metric: "http.rpm", applicationId: "4", scopeId: "5", groupBy: "", period: "60" });
    expect(metricArguments({ metric: "x", application_id: "4", group_by: ["instance_id", "scope_id"] }).groupBy).toBe("instance_id,scope_id");
    expect(() => metricArguments({ application_id: "4" })).toThrow(expect.objectContaining({ code: "MISSING_METRIC" }));
    expect(buildFilters({ applicationId: "4", scopeId: "5", deploymentId: "null" })).toBe('application_id="4",scope_id="5"');
    expect(buildFilters({ applicationId: "4", scopeId: "", deploymentId: "6" })).toBe('application_id="4",deployment_id="6"');
  });
});

describe("buildQuery", () => {
  const f = 'application_id="4",scope_id="5"';
  test("reproduces the bash's PromQL", () => {
    expect(buildQuery("http.rpm", f, "5m", "", "5")).toBe(`sum(rate(nullplatform_http_response_time_count{${f}}[5m])) * 60`);
    expect(buildQuery("http.rpm", f, "5m", "instance_id", "5")).toBe(`sum(rate(nullplatform_http_response_time_count{${f}}[5m])) by (instance_id) * 60`);
    expect(buildQuery("http.response_time", f, "5m", "", "5")).toBe(`sum(idelta(nullplatform_http_response_time{${f}}[5m]))/sum(idelta(nullplatform_http_response_time_count{${f}}[5m]))`);
    expect(buildQuery("http.error_rate", f, "5m", "", "5")).toBe(`((sum(rate(nullplatform_http_response_time_count{${f}}[5m])) * 60 - sum(rate(nullplatform_http_response_time_count{${f},quality="OK (2XX, 3XX)"}[5m])) * 60) / (sum(rate(nullplatform_http_response_time_count{${f}}[5m])) * 60 )) *100`);
    expect(buildQuery("http.healthcheck_count", f, "5m", "", "5")).toBe(`sum(rate(nullplatform_http_response_time_count{${f},is_healthcheck="yes"}[5m]))`);
    expect(buildQuery("system.cpu_usage_percentage", f, "5m", "", "5")).toBe(`avg(nullplatform_system_cpu_usage_percentage{${f}})`);
    expect(buildQuery("system.memory_usage_percentage", f, "5m", "scope_id", "5")).toBe(`avg(nullplatform_system_memory_usage_percentage{${f}}) by (scope_id)`);
    expect(buildQuery("system.cpu_usage_percentage_by_instance", f, "5m", "", "5")).toBe(`avg(nullplatform_system_cpu_usage_percentage{${f}}) by (instance_id)`);
    expect(buildQuery("cronjob.success_count", f, "1h", "", "5")).toBe('sum by (scope_id) (label_replace(increase(kube_job_status_succeeded{job_name=~"job-5-.*"}[1h]), "scope_id", "$1", "job_name", "job-([0-9]+)-.*"))');
    expect(buildQuery("whatever", f, "5m", "", "5")).toBe(`up{${f}}`);
  });
});

describe("timeWindow", () => {
  const span = { startTime: "2026-10-20T12:00:00.000Z", endTime: "2026-10-20T13:00:00.000Z", timeRange: "", interval: "" };
  test("with a span the step is the period and the rate range is period/60 minutes, 5m at least for http", () => {
    expect(timeWindow({ metric: "system.cpu_usage_percentage", ...span, period: "120" })).toEqual({ start: 1792497600, end: 1792501200, step: 120, interval: "2m" });
    expect(timeWindow({ metric: "http.rpm", ...span, period: "60" })).toEqual({ start: 1792497600, end: 1792501200, step: 60, interval: "5m" });
    expect(timeWindow({ metric: "http.rpm", ...span, period: "" })).toEqual({ start: 1792497600, end: 1792501200, step: 60, interval: "5m" });
  });
  test("without a span the window ends now and reaches back time_range, stepping by interval", () => {
    const now = Date.parse("2026-10-20T13:00:00Z");
    expect(timeWindow({ metric: "http.rpm", startTime: "", endTime: "", period: "", timeRange: "6h", interval: "5m" }, now)).toEqual({ start: 1792501200 - 6 * 3600, end: 1792501200, step: 300, interval: "5m" });
    expect(timeWindow({ metric: "http.rpm", startTime: "", endTime: "", period: "", timeRange: "", interval: "" }, now)).toEqual({ start: 1792501200 - 3600, end: 1792501200, step: 60, interval: "5m" });
  });
});

describe("readMetric", () => {
  test("shapes the answer as the bash did and leaves non-numeric points out", async () => {
    const prometheus = inMemoryPrometheus(sampleSeries());
    const answer = await readMetric({ prometheus, prometheusUrl: async () => "http://prom" }, { metric: "http.rpm", application_id: "4", scope_id: "5", start_time: "2026-10-20T12:00:00.000Z", end_time: "2026-10-20T13:00:00.000Z", period: 60, group_by: ["instance_id"] });
    expect(answer).toEqual({ metric: "http.rpm", type: "gauge", period_in_seconds: 60, unit: "count_per_minute", results: [{ selector: { instance_id: "d-6-a" }, data: [{ timestamp: "2026-10-20T12:00:00Z", value: 0.5 }, { timestamp: "2026-10-20T12:01:00Z", value: 0.7 }] }] });
    expect(prometheus.queries[0]).toEqual({ query: 'sum(rate(nullplatform_http_response_time_count{application_id="4",scope_id="5"}[5m])) by (instance_id) * 60', start: 1792497600, end: 1792501200, step: 60 });
    expect(todate(0)).toBe("1970-01-01T00:00:00Z");
    expect(transformResponse({ status: "error", error: "bad" })).toEqual([]);
  });

  test("no Prometheus is a named error", async () => {
    await expect(readMetric({ prometheus: inMemoryPrometheus([]), prometheusUrl: async () => "" }, { metric: "http.rpm", application_id: "4" })).rejects.toMatchObject({ code: "NO_PROMETHEUS" });
  });
});
