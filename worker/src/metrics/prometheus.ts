/** The Prometheus port: one range query, as `GET /api/v1/query_range` answers it. */

export interface PrometheusSeries {
  metric: Record<string, string>;
  values: Array<[number, string]>;
}

export interface PrometheusRangeResponse {
  status: string;
  data?: { resultType?: string; result?: PrometheusSeries[] };
  error?: string;
  errorType?: string;
}

export interface PrometheusClient {
  queryRange(baseUrl: string, query: string, start: number, end: number, stepSeconds: number, signal?: AbortSignal): Promise<PrometheusRangeResponse>;
}

export class PrometheusError extends Error {
  constructor(
    readonly status: number,
    body: string,
  ) {
    super(`prometheus answered ${status}: ${body.slice(0, 300)}`);
    this.name = "PrometheusError";
  }
}

export function prometheusClient(options: { timeoutMs?: number } = {}): PrometheusClient {
  const timeoutMs = options.timeoutMs ?? 20_000;
  return {
    async queryRange(baseUrl, query, start, end, stepSeconds, signal) {
      const params = new URLSearchParams({ query, start: String(start), end: String(end), step: `${stepSeconds}s` });
      const signals = [AbortSignal.timeout(timeoutMs), ...(signal ? [signal] : [])];
      const response = await fetch(`${baseUrl.replace(/\/$/, "")}/api/v1/query_range?${params}`, {
        headers: { Accept: "application/json" },
        signal: signals.length === 1 ? signals[0] : AbortSignal.any(signals),
      });
      if (!response.ok) {
        // Prometheus explains a bad query in its JSON body; a proxy's error page is text.
        const body = await response.text();
        try {
          return JSON.parse(body) as PrometheusRangeResponse;
        } catch {
          throw new PrometheusError(response.status, body);
        }
      }
      return (await response.json()) as PrometheusRangeResponse;
    },
  };
}

/** A Prometheus that answers every query with the same series. For tests and `src/local.ts`. */
export function inMemoryPrometheus(series: PrometheusSeries[] | ((query: string) => PrometheusSeries[])): PrometheusClient & { queries: Array<{ query: string; start: number; end: number; step: number }> } {
  const queries: Array<{ query: string; start: number; end: number; step: number }> = [];
  return {
    queries,
    async queryRange(_baseUrl, query, start, end, step) {
      queries.push({ query, start, end, step });
      return { status: "success", data: { resultType: "matrix", result: typeof series === "function" ? series(query) : series } };
    },
  };
}
