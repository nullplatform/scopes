import { describe, expect, test } from "bun:test";
import type { Context } from "@nullplatform/plugin";
import { DATADOG_METRICS, datadogConfig, datadogFilters, datadogKeysOf, datadogQuery, datadogWindow, readDatadogMetric, timeseriesRequest, traceTargetOf, transformDatadog } from "../src/metrics/datadog";

const WINDOW = { start: 1792497600, end: 1792501200, step: 60 };
const TRACE = { environment: "prod", repositoryName: "checkout" };
const F = "application_id:4,scope_id:5";

describe("the Datadog catalog and units", () => {
  test("lists the seven metrics the overlay advertised, with the overlay's units", () => {
    expect(DATADOG_METRICS.map((metric) => metric.name)).toEqual(["http.rpm", "http.response_time", "http.error_rate", "system.cpu_usage_percentage", "system.memory_usage_percentage", "http.healthcheck_count", "http.healthcheck_fail"]);
    expect(datadogConfig("trace.http.request.p99")).toEqual({ type: "gauge", unit: "milliseconds" });
    expect(datadogConfig("nope")).toEqual({ type: "gauge", unit: "unknown" });
  });
});

describe("the queries", () => {
  test("are the overlay's, tag filters and a by clause from the group", () => {
    expect(datadogFilters({ applicationId: "4", scopeId: "5", deploymentId: "null" })).toBe(F);
    expect(datadogFilters({ applicationId: "4", scopeId: "", deploymentId: "6" })).toBe("application_id:4,deployment_id:6");
    expect(datadogQuery("http.rpm", F, WINDOW, "", TRACE)).toBe(`sum:nullplatform.scope.request_count{${F}}.rollup(sum, 60)`);
    expect(datadogQuery("http.rpm", F, WINDOW, "instance_id, scope_id", TRACE)).toBe(`sum:nullplatform.scope.request_count{${F}} by {instance_id,scope_id}.rollup(sum, 60)`);
    expect(datadogQuery("http.response_time", F, WINDOW, "", TRACE)).toBe(`sum:nullplatform.scope.response_time{${F}}.rollup(sum, 60) / sum:nullplatform.scope.request_count{${F}}.rollup(sum, 60)`);
    expect(datadogQuery("http.error_rate", F, WINDOW, "", TRACE)).toBe(`((sum:nullplatform.scope.request_count{${F}}.rollup(sum, 60) - sum:nullplatform.scope.request_count{${F},quality:ok_2xx_3xx}.rollup(sum, 60)) / sum:nullplatform.scope.request_count{${F}}.rollup(sum, 60)) * 100`);
    expect(datadogQuery("http.healthcheck_count", F, { ...WINDOW, step: 30 }, "", TRACE)).toBe(`sum:nullplatform.scope.request_count{${F},is_healthcheck:yes} by {instance_id}.rollup(sum, 30)`);
    expect(datadogQuery("http.healthcheck_fail", F, WINDOW, "", TRACE)).toBe(`sum:nullplatform.scope.request_count{${F},is_healthcheck:yes} by {instance_id}.rollup(sum, 60) - sum:nullplatform.scope.request_count{${F},is_healthcheck:yes,quality:ok_2xx_3xx} by {instance_id}.rollup(sum, 60)`);
    expect(datadogQuery("system.memory_usage_percentage", F, WINDOW, "scope_id", TRACE)).toBe(`avg:nullplatform.scope.memory_usage_percentage{${F}} by {scope_id}`);
    expect(datadogQuery("system.cpu_usage_percentage", F, WINDOW, "", TRACE)).toBe(`avg:nullplatform.scope.cpu_usage_percentage{${F}}`);
    expect(datadogQuery("system.used_memory_kb", F, WINDOW, "", TRACE)).toBe(`avg:nullplatform.scope.memory_usage_kb{${F}}`);
    expect(datadogQuery("trace.http.request.p99", F, WINDOW, "", TRACE)).toBe("p99:trace.http.request{service:checkout-kubernetes,env:prod}.rollup(avg, 3600) * 1000");
    expect(datadogQuery("p95:trace.http.request", F, WINDOW, "", TRACE)).toBe("p95:trace.http.request{service:checkout-kubernetes,env:prod}.rollup(avg, 3600) * 1000");
    expect(datadogQuery("custom.metric", F, WINDOW, "instance_id", TRACE)).toBe(`avg:custom.metric{${F}} by {instance_id}`);
  });

  test("the trace target is the service's environment and the repository's name", () => {
    expect(traceTargetOf({ service: { dimensions: { environment: "prod" } }, tags: { repository_url: "https://github.com/acme/checkout/" } })).toEqual(TRACE);
    expect(traceTargetOf({})).toEqual({ environment: "", repositoryName: "" });
  });
});

describe("the window", () => {
  test("is the span given, stepping by the period, else 30 s for six minutes or less, else 60; else time_range back from now", () => {
    expect(datadogWindow({ startTime: "2026-10-20T12:00:00.000Z", endTime: "2026-10-20T13:00:00.000Z", period: "120", timeRange: "" })).toEqual({ start: 1792497600, end: 1792501200, step: 120 });
    expect(datadogWindow({ startTime: "2026-10-20T12:00:00Z", endTime: "2026-10-20T12:05:00Z", period: "", timeRange: "" })).toEqual({ start: 1792497600, end: 1792497900, step: 30 });
    expect(datadogWindow({ startTime: "2026-10-20T12:00:00Z", endTime: "2026-10-20T13:00:00Z", period: "", timeRange: "" }).step).toBe(60);
    const now = Date.parse("2026-10-20T13:00:00Z");
    expect(datadogWindow({ startTime: "", endTime: "", period: "", timeRange: "6h" }, now)).toEqual({ start: 1792501200 - 6 * 3600, end: 1792501200, step: 60 });
    expect(datadogWindow({ startTime: "", endTime: "", period: "", timeRange: "" }, now)).toEqual({ start: 1792501200 - 3600, end: 1792501200, step: 60 });
    expect(timeseriesRequest("q", WINDOW)).toEqual({ data: { type: "timeseries_request", attributes: { formulas: [{ formula: "a" }], queries: [{ name: "a", query: "q", data_source: "metrics" }], from: 1792497600000, to: 1792501200000, interval: 60000 } } });
  });
});

describe("the answer", () => {
  test("is one result per series, its tags the selector, a point per time, 0 where Datadog has none, nothing on an error", () => {
    const response = { data: { attributes: { series: [{ group_tags: ["instance_id:d-6-a", "scope_id:5"] }, { scope: "instance_id:d-6-b,scope_id:5" }, { group_tags: {} }], times: [1792497600000, 1792497660000], values: [[0.5, null], [1, 2], [3]] } } };
    expect(transformDatadog(response)).toEqual([
      { selector: { instance_id: "d-6-a", scope_id: "5" }, data: [{ timestamp: "2026-10-20T12:00:00Z", value: 0.5 }, { timestamp: "2026-10-20T12:01:00Z", value: 0 }] },
      { selector: { instance_id: "d-6-b", scope_id: "5" }, data: [{ timestamp: "2026-10-20T12:00:00Z", value: 1 }, { timestamp: "2026-10-20T12:01:00Z", value: 2 }] },
      { selector: {}, data: [{ timestamp: "2026-10-20T12:00:00Z", value: 3 }, { timestamp: "2026-10-20T12:01:00Z", value: 0 }] },
    ]);
    expect(transformDatadog({ errors: ["bad query"] })).toEqual([]);
    expect(transformDatadog({ data: { attributes: { series: [] } } })).toEqual([]);
  });
});

describe("the keys", () => {
  const contextWith = (providers: unknown[]): Context => ({ api: { scope: () => ({ get: async () => ({ nrn: "organization=1" }) }), provider: { list: () => ({ [Symbol.asyncIterator]: async function* () { yield { results: providers }; } }) } }, log: { debug() {}, info() {}, warn() {}, error() {} } }) as unknown as Context;

  test("come from the environment, else from the organization's metrics provider; neither is a named error", async () => {
    expect(await datadogKeysOf({ DATADOG_API_KEY: "a", DATADOG_APP_KEY: "b" })(contextWith([]), "5")).toEqual({ apiKey: "a", appKey: "b", site: "datadoghq.com" });
    const provided = await datadogKeysOf({})(contextWith([{ attributes: { credentials: { api_key: "pa", app_key: "pb" }, settings: { site: "datadoghq.eu" } } }]), "scope-with-provider");
    expect(provided).toEqual({ apiKey: "pa", appKey: "pb", site: "datadoghq.eu" });
    await expect(datadogKeysOf({})(contextWith([]), "scope-without")).rejects.toMatchObject({ code: "NO_DATADOG" });
    await expect(datadogKeysOf({})(contextWith([{ attributes: { credentials: { api_key: "pa" } } }]), "scope-half")).rejects.toMatchObject({ code: "NO_DATADOG_APP_KEY" });
  });
});

describe("readDatadogMetric", () => {
  test("asks the timeseries API at the site with both keys and shapes the answer as the overlay did", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const fetchFake = (async (url: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(url), init: init ?? {} });
      return new Response(JSON.stringify({ data: { attributes: { series: [{ group_tags: ["instance_id:d-6-a"] }], times: [1792497600000], values: [[12]] } } }));
    }) as typeof fetch;
    const context = { api: {}, log: {} } as unknown as Context;
    const answer = await readDatadogMetric({ fetch: fetchFake, keys: async () => ({ apiKey: "api", appKey: "app", site: "datadoghq.com" }) }, { metric: "http.rpm", application_id: "4", scope_id: "5", start_time: "2026-10-20T12:00:00.000Z", end_time: "2026-10-20T13:00:00.000Z", period: 60, group_by: ["instance_id"] }, { service: { dimensions: { environment: "prod" } } }, context);
    expect(answer).toEqual({ metric: "http.rpm", type: "gauge", period_in_seconds: 60, unit: "count_per_minute", results: [{ selector: { instance_id: "d-6-a" }, data: [{ timestamp: "2026-10-20T12:00:00Z", value: 12 }] }] });
    expect(calls[0].url).toBe("https://api.datadoghq.com/api/v2/query/timeseries");
    expect(calls[0].init.headers).toMatchObject({ "DD-API-KEY": "api", "DD-APPLICATION-KEY": "app" });
    expect(JSON.parse(calls[0].init.body as string).data.attributes.queries[0].query).toBe("sum:nullplatform.scope.request_count{application_id:4,scope_id:5} by {instance_id}.rollup(sum, 60)");
  });
});
