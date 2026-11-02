/**
 * The Kubernetes port: pods by label, one pod by name, one pod's log. The real client takes
 * its cluster, credentials and TLS material from `@kubernetes/client-node`'s KubeConfig
 * (kubeconfig, exec plugins such as `aws eks get-token` or `kubelogin`, in-cluster service
 * account) and makes the requests with Bun's fetch: the client's own transport hands TLS
 * client certificates to an undici dispatcher that Bun ignores, and its generated
 * readNamespacedPodLog has no sinceTime. Connections are reused by Bun; the config is loaded
 * once, lazily, so `--describe` never needs a cluster.
 */

import type { KubeConfig } from "@kubernetes/client-node";
import type { RequestOptions } from "node:https";
import type { Pod, PodList } from "./types";

export interface LogReadOptions {
  container: string;
  /** RFC3339; the API resumes at this second. */
  sinceTime?: string;
  /** The API cuts the log at this many bytes, wherever the cut falls. */
  limitBytes: number;
  signal?: AbortSignal;
}

export interface KubeClient {
  /** The pods matching `labelSelector` in `namespace`, or in every namespace when none is given. */
  listPods(namespace: string | undefined, labelSelector: string, signal?: AbortSignal): Promise<Pod[]>;
  /** One pod by name, in `namespace` or anywhere; null when there is none. */
  getPod(namespace: string | undefined, name: string, signal?: AbortSignal): Promise<Pod | null>;
  /** The pod's log as the API returns it, cut at `limitBytes`; "" when the container has none. */
  readLog(pod: Pod, options: LogReadOptions): Promise<string>;
}

export class KubeApiError extends Error {
  constructor(
    readonly status: number,
    readonly path: string,
    body: string,
  ) {
    super(`kubernetes api answered ${status} on ${path}: ${body.slice(0, 300)}`);
    this.name = "KubeApiError";
  }
}

export interface KubeClientOptions {
  /** A loaded KubeConfig; by default `loadFromDefault()` on first use. */
  kubeConfig?: () => Promise<KubeConfig> | KubeConfig;
  /** The kubeconfig context to use, when not its current one. */
  context?: string;
  /** Each request's deadline. */
  timeoutMs?: number;
  /** How long a pod listing is reused by the calls that arrive together (logs, metrics, instances). */
  listCacheMs?: number;
}

interface TlsInit {
  ca?: string | Buffer | Array<string | Buffer>;
  cert?: string | Buffer | Array<string | Buffer>;
  key?: string | Buffer | Array<string | Buffer>;
  rejectUnauthorized?: boolean;
  serverName?: string;
}

const encode = (value: string): string => encodeURIComponent(value);

/** Every signal given, as one; a timeout always among them. */
function deadline(timeoutMs: number, ...signals: Array<AbortSignal | undefined>): AbortSignal {
  const all = [AbortSignal.timeout(timeoutMs), ...signals.filter((signal): signal is AbortSignal => signal !== undefined)];
  return all.length === 1 ? all[0] : AbortSignal.any(all);
}

async function loadDefault(context: string | undefined): Promise<KubeConfig> {
  const { KubeConfig: Config } = await import("@kubernetes/client-node");
  const config = new Config();
  config.loadFromDefault();
  if (context) {
    config.setCurrentContext(context);
  }
  return config;
}

export function kubeClient(options: KubeClientOptions = {}): KubeClient {
  const timeoutMs = options.timeoutMs ?? 10_000;
  const listCacheMs = options.listCacheMs ?? 1_500;
  let loaded: Promise<KubeConfig> | undefined;
  const config = (): Promise<KubeConfig> => (loaded ??= Promise.resolve(options.kubeConfig ? options.kubeConfig() : loadDefault(options.context)));
  const listings = new Map<string, { at: number; pods: Promise<Pod[]> }>();

  async function request(path: string, signal: AbortSignal | undefined): Promise<Response> {
    const kc = await config();
    const cluster = kc.getCurrentCluster();
    if (!cluster) {
      throw new Error("the kubeconfig names no current cluster: select a context (kubectl config use-context, or KUBE_CONTEXT)");
    }
    // The client fills the Authorization header (running an exec plugin when the context has one,
    // cached until the token expires), the CA, the client certificate and key.
    const auth: RequestOptions = {};
    await kc.applyToHTTPSOptions(auth);
    const headers = new Headers({ Accept: "application/json" });
    for (const [name, value] of Object.entries(auth.headers ?? {})) {
      if (typeof value === "string") {
        headers.set(name, value);
      }
    }
    const tls: TlsInit = {};
    if (auth.ca !== undefined) tls.ca = auth.ca as TlsInit["ca"];
    if (auth.cert !== undefined) tls.cert = auth.cert as TlsInit["cert"];
    if (auth.key !== undefined) tls.key = auth.key as TlsInit["key"];
    if (auth.rejectUnauthorized !== undefined) tls.rejectUnauthorized = auth.rejectUnauthorized;
    if (auth.servername !== undefined) tls.serverName = auth.servername;
    const init = { headers, signal: deadline(timeoutMs, signal), tls } as RequestInit & { tls: TlsInit };
    return fetch(cluster.server.replace(/\/$/, "") + path, init);
  }

  async function json<T>(path: string, signal: AbortSignal | undefined): Promise<T> {
    const response = await request(path, signal);
    if (!response.ok) {
      throw new KubeApiError(response.status, path, await response.text());
    }
    return (await response.json()) as T;
  }

  return {
    listPods(namespace, labelSelector, signal) {
      const path = namespace === undefined ? `/api/v1/pods?labelSelector=${encode(labelSelector)}` : `/api/v1/namespaces/${encode(namespace)}/pods?labelSelector=${encode(labelSelector)}`;
      const now = Date.now();
      const cached = listings.get(path);
      if (cached && now - cached.at < listCacheMs) {
        return cached.pods;
      }
      const pods = json<PodList>(path, signal).then((list) => list.items ?? []);
      listings.set(path, { at: now, pods });
      pods.catch(() => listings.delete(path));
      return pods;
    },

    async getPod(namespace, name, signal) {
      if (namespace === undefined) {
        const list = await json<PodList>(`/api/v1/pods?fieldSelector=${encode(`metadata.name=${name}`)}`, signal);
        return list.items?.[0] ?? null;
      }
      const response = await request(`/api/v1/namespaces/${encode(namespace)}/pods/${encode(name)}`, signal);
      if (response.status === 404) {
        return null;
      }
      if (!response.ok) {
        throw new KubeApiError(response.status, `/api/v1/namespaces/${namespace}/pods/${name}`, await response.text());
      }
      return (await response.json()) as Pod;
    },

    async readLog(pod, { container, sinceTime, limitBytes, signal }) {
      const query = new URLSearchParams({ container, timestamps: "true", limitBytes: String(limitBytes) });
      if (sinceTime) {
        query.set("sinceTime", sinceTime);
      }
      const path = `/api/v1/namespaces/${encode(pod.metadata.namespace)}/pods/${encode(pod.metadata.name)}/log?${query}`;
      const response = await request(path, signal);
      if (response.status === 400 || response.status === 404) {
        // No such container, or a pod that is gone or not started: nothing to read, as the Go logger treated a failed stream.
        await response.text();
        return "";
      }
      if (!response.ok) {
        throw new KubeApiError(response.status, path, await response.text());
      }
      return response.text();
    },
  };
}
