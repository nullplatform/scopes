import { describe, expect, test } from "bun:test";
import { cores, instanceOf, listInstances } from "../src/instances/list";
import { inMemoryKube } from "../src/kube/in-memory";
import { pod, samplePods } from "./sample";

describe("instances", () => {
  test("cpu is read in cores whatever the unit", () => {
    expect(cores("500m")).toBe(0.5);
    expect(cores("1")).toBe(1);
    expect(cores("0.25")).toBe(0.25);
    expect(cores(undefined)).toBe(0);
  });

  test("a pod becomes an instance as the bash shaped it, with what it lacked inside details", () => {
    const instance = instanceOf(pod("d-6-a", "uid-a"));
    expect(instance).toMatchObject({
      id: "d-6-a",
      selector: { application_id: "4", scope_id: "5", deployment_id: "6" },
      details: { namespace: "nullplatform", ip: "10.0.0.5", dns: "10.0.0.5.nullplatform.pod.cluster.local", cpu: { requested: 0.25, limit: 1 }, memory: { requested: "256Mi", limit: "512Mi" }, architecture: "x86", node: "node-a", ready: true, restarts: 0 },
      state: "Running",
      launch_time: "2026-10-20T11:00:00Z",
      spot: false,
    });
  });

  test("a pending pod has no ip, an arm image is arm64, a spot node is spot", () => {
    const pending = instanceOf(pod("p", "u", { status: { phase: "Pending", containerStatuses: [{ name: "application", image: "img:arm64", restartCount: 3 }] }, spec: { nodeName: "aks-spot-1" } }));
    expect(pending.details).toMatchObject({ ip: "pending", dns: "pending", architecture: "arm64", restarts: 3, cpu: { requested: 0, limit: 0 } });
    expect(pending.spot).toBe(true);
    expect(pending.state).toBe("Pending");
  });

  test("filters arrive as arrays and limit cuts the list", async () => {
    const kube = inMemoryKube({ pods: samplePods() });
    const all = await listInstances({ kube, namespace: undefined }, { application_id: ["4"], scope_id: ["5"] });
    expect(all.results.map((i) => i.id)).toEqual(["d-6-a", "d-6-b"]);
    const one = await listInstances({ kube, namespace: undefined }, { application_id: ["4"], scope_id: ["5"], limit: "1" });
    expect(one.results).toHaveLength(1);
    const none = await listInstances({ kube, namespace: undefined }, { application_id: ["9"] });
    expect(none.results).toEqual([]);
  });
});
