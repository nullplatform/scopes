/**
 * An in-memory Kubernetes: pods, and each pod's log lines, answering as the API does on a
 * read (lines from the second of `sinceTime` on, cut at `limitBytes` bytes). For the tests
 * and for `src/local.ts`; nothing here reaches a cluster.
 */

import type { KubeClient, LogReadOptions } from "./client";
import type { Pod } from "./types";

export interface InMemoryCluster {
  pods: Pod[];
  /** Each pod's log lines, by pod name, as the kubelet prints them: an RFC3339 timestamp, a space, the message. */
  logs?: Record<string, string[]>;
}

/** The second a timestamp falls in, as the API resumes a read at the second of sinceTime, not at the instant. */
const secondOf = (timestamp: string): number => Math.floor(Date.parse(timestamp) / 1000);

/** Whether `pod` carries every label of the selector (`key=value,key=value`). */
function matches(pod: Pod, selector: string): boolean {
  const labels = pod.metadata.labels ?? {};
  return selector.split(",").every((part) => {
    const [key, value] = part.split("=");
    return labels[key] === value;
  });
}

export function inMemoryKube(cluster: InMemoryCluster): KubeClient & { reads: LogReadOptions[] } {
  const reads: LogReadOptions[] = [];
  return {
    reads,
    async listPods(namespace, labelSelector) {
      return cluster.pods.filter((pod) => (namespace === undefined || pod.metadata.namespace === namespace) && matches(pod, labelSelector));
    },
    async getPod(namespace, name) {
      return cluster.pods.find((pod) => pod.metadata.name === name && (namespace === undefined || pod.metadata.namespace === namespace)) ?? null;
    },
    async readLog(pod, options) {
      reads.push(options);
      const lines = cluster.logs?.[pod.metadata.name] ?? [];
      const since = options.sinceTime ? secondOf(options.sinceTime) : -Infinity;
      const text = lines.filter((line) => secondOf(line.slice(0, line.indexOf(" "))) >= since).map((line) => line + "\n").join("");
      return Buffer.from(text).subarray(0, options.limitBytes).toString("utf8");
    },
  };
}
