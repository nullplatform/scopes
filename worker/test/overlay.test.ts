import { describe, expect, test } from "bun:test";
import { overlayWorkflow, TELEMETRY_WORKFLOWS } from "../src/overlay";

describe("an overlay's workflows", () => {
  const datadog = new Set(["/app/pkg/datadog/metric/workflows/metric.yaml", "/app/pkg/datadog/metric/workflows/list.yaml"]);
  const exists = (path: string) => datadog.has(path);

  test("take the telemetry actions they have a workflow for, and no other", () => {
    expect(overlayWorkflow("metric:data", ["/app/pkg/datadog"], exists)).toBe("/app/pkg/datadog/metric/workflows/metric.yaml");
    expect(overlayWorkflow("metric:list", ["/app/pkg/datadog"], exists)).toBe("/app/pkg/datadog/metric/workflows/list.yaml");
    expect(overlayWorkflow("log:read", ["/app/pkg/datadog"], exists)).toBeUndefined();
    expect(overlayWorkflow("instance:data", ["/app/pkg/datadog"], exists)).toBeUndefined();
  });

  test("the first overlay that has the workflow wins, and an action that is not telemetry is never theirs here", () => {
    expect(overlayWorkflow("metric:data", ["/app/pkg/azure", "/app/pkg/datadog"], exists)).toBe("/app/pkg/datadog/metric/workflows/metric.yaml");
    expect(overlayWorkflow("metric:data", [], exists)).toBeUndefined();
    expect(overlayWorkflow("service:action:create", ["/app/pkg/datadog"], () => true)).toBeUndefined();
    expect(Object.keys(TELEMETRY_WORKFLOWS)).toEqual(["log:read", "metric:list", "metric:data", "instance:data"]);
  });
});
