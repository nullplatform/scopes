/** An in-memory cluster of the fixtures' scope: two pods of application 4, scope 5, deployment 6, and their logs. */
import type { Pod } from "../src/kube/types";
import type { PrometheusSeries } from "../src/metrics/prometheus";

export const LABELS = { nullplatform: "true", application_id: "4", scope_id: "5", deployment_id: "6", account_id: "2", namespace_id: "3", name: "d-6" };

export function pod(name: string, uid: string, extra: Partial<Pod> = {}): Pod {
  return {
    metadata: { name, uid, namespace: "nullplatform", labels: LABELS, creationTimestamp: "2026-10-20T11:00:00Z" },
    spec: { nodeName: "node-a", containers: [{ name: "application", image: "ghcr.io/acme/checkout:1.2.3", resources: { requests: { cpu: "250m", memory: "256Mi" }, limits: { cpu: "1", memory: "512Mi" } } }] },
    status: { phase: "Running", podIP: "10.0.0.5", containerStatuses: [{ name: "application", image: "ghcr.io/acme/checkout:1.2.3", ready: true, restartCount: 0 }] },
    ...extra,
  };
}

export const samplePods = (): Pod[] => [pod("d-6-a", "uid-a"), pod("d-6-b", "uid-b")];

/** `count` lines, one per second from `startIso`, `pad` characters each. */
export function lines(startIso: string, count: number, prefix: string, pad = 0): string[] {
  const start = Date.parse(startIso);
  return Array.from({ length: count }, (_, index) => `${new Date(start + index * 1000).toISOString().replace("Z", "000000Z")} ${prefix} ${index}${pad ? " " + "x".repeat(pad) : ""}`);
}

export const sampleLogs = (): Record<string, string[]> => ({
  "d-6-a": lines("2026-10-20T12:00:00.000Z", 25, "a"),
  "d-6-b": lines("2026-10-20T12:00:00.500Z", 5, "b"),
});

export const sampleSeries = (): PrometheusSeries[] => [{ metric: { instance_id: "d-6-a" }, values: [[1792497600, "0.5"], [1792497660, "0.7"], [1792497720, "NaN"]] }];
