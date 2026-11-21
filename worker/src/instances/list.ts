/**
 * instance:data: the pods of the scope as instances, the port of k8s/instance/list. The
 * telemetry API keeps `selector`, `state`, `launch_time`, `id`, `details` and `spot`; what the
 * bash never had (restarts, readiness, the node) rides inside `details`.
 */

import type { KubeClient } from "../kube/client";
import type { Pod, PodContainer, PodContainerStatus } from "../kube/types";
import { text } from "../logs/arguments";
import { labelSelector } from "../logs/arguments";

export interface InstancePorts {
  kube: KubeClient;
  namespace: string | undefined;
}

export interface Instance {
  id: string;
  selector: Record<string, string>;
  details: {
    namespace: string;
    ip: string;
    dns: string;
    cpu: { requested: number; limit: number };
    memory: { requested: string; limit: string };
    architecture: "arm64" | "x86";
    node: string;
    ready: boolean;
    restarts: number;
  };
  state: string;
  launch_time: string;
  spot: boolean;
}

/** CPU in cores: `500m` is 0.5, `1` is 1, `0.5` is 0.5, nothing is 0. */
export function cores(value: string | undefined): number {
  if (!value) {
    return 0;
  }
  if (value.endsWith("m")) {
    return Number(value.slice(0, -1)) / 1000;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

/** The `application` container's entry, else the first; the pod's app is the container named for it. */
function applicationEntry<T extends { name: string }>(entries: T[] | undefined): T | undefined {
  return entries?.find((entry) => entry.name === "application") ?? entries?.[0];
}

export function instanceOf(pod: Pod): Instance {
  const app: PodContainer | undefined = applicationEntry(pod.spec?.containers);
  const status: PodContainerStatus | undefined = applicationEntry(pod.status?.containerStatuses);
  const namespace = pod.metadata.namespace;
  const ip = pod.status?.podIP;
  return {
    id: pod.metadata.name,
    selector: pod.metadata.labels ?? {},
    details: {
      namespace,
      ip: ip ?? "pending",
      dns: ip ? `${ip}.${namespace}.pod.cluster.local` : "pending",
      cpu: { requested: cores(app?.resources?.requests?.cpu), limit: cores(app?.resources?.limits?.cpu) },
      memory: { requested: app?.resources?.requests?.memory ?? "0Mi", limit: app?.resources?.limits?.memory ?? "0Mi" },
      architecture: /arm64|aarch64/.test(status?.image ?? "") ? "arm64" : "x86",
      node: pod.spec?.nodeName ?? "",
      ready: status?.ready ?? false,
      restarts: status?.restartCount ?? 0,
    },
    state: pod.status?.phase ?? "Unknown",
    launch_time: pod.metadata.creationTimestamp ?? "",
    spot: /spot/i.test(pod.spec?.nodeName ?? ""),
  };
}

export async function listInstances(ports: InstancePorts, raw: Record<string, unknown> | undefined, signal?: AbortSignal): Promise<{ results: Instance[] }> {
  const args = raw ?? {};
  const ids = { applicationId: text(args.application_id), scopeId: text(args.scope_id), deploymentId: text(args.deployment_id) };
  const limitText = text(args.limit);
  const limit = /^\d+$/.test(limitText) ? Number(limitText) : 0;
  const pods = await ports.kube.listPods(ports.namespace, labelSelector(ids), signal);
  const kept = limit > 0 ? pods.slice(0, limit) : pods;
  return { results: kept.map(instanceOf) };
}
