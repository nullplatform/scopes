import { describe, expect, test } from "bun:test";
import { run } from "@nullplatform/plugin/testing";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inMemoryKube } from "../src/kube/in-memory";
import { datadogBackend, prometheusBackend, type MetricsBackend } from "../src/metrics/backend";
import { inMemoryPrometheus } from "../src/metrics/prometheus";
import instanceData from "../src/samples/instance-data.json" with { type: "json" };
import logRead from "../src/samples/log-read.json" with { type: "json" };
import metricData from "../src/samples/metric-data.json" with { type: "json" };
import metricListFixture from "../src/samples/metric-list.json" with { type: "json" };
import startInitial from "../src/samples/start-initial.json" with { type: "json" };
import { documentOf, scopeWorker } from "../src/worker";
import { sampleLogs, samplePods, sampleSeries } from "./sample";

/** An image's layout in a temp dir: the entrypoint, which prints the action it got. */
const image = mkdtempSync(join(tmpdir(), "scopes-image-"));
const entrypoint = join(image, "entrypoint");
writeFileSync(entrypoint, `#!/usr/bin/env bash\naction=$(echo "$NP_ACTION_CONTEXT" | sed -E 's/.*"action":"([^"]+)".*/\\1/')\necho "bash answered $action with $*"\n`);

const PROVIDER = "34ef2d7d-bde1-453c-a7c8-4e33f7b2f6d3";
const worker = (metrics: MetricsBackend = prometheusBackend(inMemoryPrometheus(sampleSeries()), "http://prometheus.local"), overridesPaths: string[] = []) =>
  scopeWorker(
    {
      package: { name: "containers", version: "1.2.3" },
      sources: ["service", "telemetry"],
      entrypoint: { path: entrypoint, servicePath: join(image, "k8s"), overridesPaths },
      scopeProviders: [PROVIDER],
      namespace: undefined,
    },
    { kube: inMemoryKube({ pods: samplePods(), logs: sampleLogs() }), metrics },
  );

describe("the worker", () => {
  test("is the package the image names and describes the telemetry routes before the bash one", () => {
    const plugin = worker();
    expect(plugin.package).toMatchObject({ name: "containers", version: "1.2.3" });
    expect(plugin.manifest().runs.map((entry) => entry.name)).toEqual(["log:read", "metric:list", "metric:data", "instance:data", "bash"]);
  });

  test("answers the telemetry actions itself, with no platform request", async () => {
    const plugin = worker();
    const logs = await run(plugin, logRead.notification);
    expect(logs.success).toBe(true);
    expect((logs.data as { results: unknown[] }).results).toHaveLength(30);
    expect(logs.requests).toEqual([]);
    const instances = await run(plugin, instanceData.notification);
    expect((instances.data as { results: unknown[] }).results).toHaveLength(2);
    const catalog = await run(plugin, metricListFixture.notification);
    expect((catalog.data as { results: unknown[] }).results).toHaveLength(7);
    const metric = await run(plugin, metricData.notification);
    expect((metric.data as { metric: string }).metric).toBe("http.response_time");
  });

  test("runs the bash entrypoint for a scope action, handing it the document, and answers what it printed", async () => {
    const result = await run(worker(), startInitial.notification);
    expect(result.success).toBe(true);
    const data = result.data as { exitCode: number; stdout: string; stderr: string };
    expect(data.exitCode).toBe(0);
    expect(data.stdout).toContain(`bash answered service:action:create with --service-path=${join(image, "k8s")}`);
    expect(JSON.parse(documentOf(startInitial.notification)).notification.slug).toBe("start-initial");
  });

  test("on the Datadog image, metrics come from Datadog's API and logs still from the cluster, with no bash", async () => {
    const asked: string[] = [];
    const fetchFake = (async (url: string | URL | Request, init?: RequestInit) => {
      asked.push(`${init?.method} ${String(url)} ${(init?.headers as Record<string, string>)["DD-API-KEY"]}`);
      return new Response(JSON.stringify({ data: { attributes: { series: [{ group_tags: ["instance_id:d-6-a"] }], times: [1792497600000], values: [[0.5]] } } }));
    }) as typeof fetch;
    const plugin = worker(datadogBackend({ fetch: fetchFake, keys: async () => ({ apiKey: "api", appKey: "app", site: "datadoghq.eu" }) }), [join(image, "datadog")]);
    const metric = await run(plugin, metricData.notification);
    expect(metric.data).toEqual({ metric: "http.response_time", type: "gauge", period_in_seconds: 60, unit: "seconds", results: [{ selector: { instance_id: "d-6-a" }, data: [{ timestamp: "2026-10-20T12:00:00Z", value: 0.5 }] }] });
    expect(asked).toEqual(["POST https://api.datadoghq.eu/api/v2/query/timeseries api"]);
    expect((await run(plugin, metricListFixture.notification)).data).toMatchObject({ results: expect.arrayContaining([expect.objectContaining({ name: "http.healthcheck_fail" })]) });
    const logs = await run(plugin, logRead.notification);
    expect((logs.data as { results: unknown[] }).results).toHaveLength(30);
  });

  test("a failing entrypoint is the action's failure, in its own words", async () => {
    const broken = scopeWorker({ package: { name: "containers", version: "0" }, sources: ["service"], entrypoint: { path: join(image, "missing"), servicePath: "/x", overridesPaths: [] }, scopeProviders: [], namespace: undefined }, { kube: inMemoryKube({ pods: [] }), metrics: prometheusBackend(inMemoryPrometheus([])) });
    const result = await run(broken, startInitial.notification);
    expect(result.success).toBe(false);
    expect(result.failure).toMatchObject({ code: "ENTRYPOINT_FAILED" });
  });
});
