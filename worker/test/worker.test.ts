import { describe, expect, test } from "bun:test";
import { run } from "@nullplatform/plugin/testing";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inMemoryKube } from "../src/kube/in-memory";
import { inMemoryPrometheus } from "../src/metrics/prometheus";
import instanceData from "../src/samples/instance-data.json" with { type: "json" };
import logRead from "../src/samples/log-read.json" with { type: "json" };
import metricData from "../src/samples/metric-data.json" with { type: "json" };
import metricListFixture from "../src/samples/metric-list.json" with { type: "json" };
import startInitial from "../src/samples/start-initial.json" with { type: "json" };
import { documentOf, scopeWorker } from "../src/worker";
import { sampleLogs, samplePods, sampleSeries } from "./sample";

/** An image's layout in a temp dir: the entrypoint, which prints the action it got, and an overlay with the datadog metric workflows. */
const image = mkdtempSync(join(tmpdir(), "scopes-image-"));
const entrypoint = join(image, "entrypoint");
writeFileSync(entrypoint, `#!/usr/bin/env bash\naction=$(echo "$NP_ACTION_CONTEXT" | sed -E 's/.*"action":"([^"]+)".*/\\1/')\necho "bash answered $action with $*"\nif [ "$action" = "metric:data" ]; then echo '{"results":[{"from":"datadog"}]}'; fi\n`);
mkdirSync(join(image, "datadog/metric/workflows"), { recursive: true });
writeFileSync(join(image, "datadog/metric/workflows/metric.yaml"), "steps: []\n");
writeFileSync(join(image, "datadog/metric/workflows/list.yaml"), "steps: []\n");

const PROVIDER = "34ef2d7d-bde1-453c-a7c8-4e33f7b2f6d3";
const worker = (overridesPaths: string[] = []) =>
  scopeWorker(
    {
      package: { name: "containers", version: "1.2.3" },
      sources: ["service", "telemetry"],
      entrypoint: { path: entrypoint, servicePath: join(image, "k8s"), overridesPaths },
      scopeProviders: [PROVIDER],
      namespace: undefined,
    },
    { kube: inMemoryKube({ pods: samplePods(), logs: sampleLogs() }), prometheus: inMemoryPrometheus(sampleSeries()), prometheusUrl: "http://prometheus.local" },
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

  test("leaves to the bash the telemetry action an overlay has a workflow for, and keeps the rest", async () => {
    const plugin = worker([join(image, "datadog")]);
    const metric = await run(plugin, metricData.notification);
    expect((metric.data as { stdout: string }).stdout).toContain('{"results":[{"from":"datadog"}]}');
    expect((metric.data as { stdout: string }).stdout).toContain(`--overrides-path=${join(image, "datadog")}`);
    const logs = await run(plugin, logRead.notification);
    expect((logs.data as { results: unknown[] }).results).toHaveLength(30);
  });

  test("a failing entrypoint is the action's failure, in its own words", async () => {
    const broken = scopeWorker({ package: { name: "containers", version: "0" }, sources: ["service"], entrypoint: { path: join(image, "missing"), servicePath: "/x", overridesPaths: [] }, scopeProviders: [], namespace: undefined }, { kube: inMemoryKube({ pods: [] }), prometheus: inMemoryPrometheus([]) });
    const result = await run(broken, startInitial.notification);
    expect(result.success).toBe(false);
    expect(result.failure).toMatchObject({ code: "ENTRYPOINT_FAILED" });
  });
});
