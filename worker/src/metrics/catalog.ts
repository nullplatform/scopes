/**
 * What metric:list advertises and what each metric is: the port of k8s/metric/list and of
 * get_metric_config in k8s/metric/metric. The list's units are the console's labels; the
 * config's units ride on each metric:data answer, as the bash sent them.
 */

export interface MetricDescriptor {
  name: string;
  title: string;
  unit: string;
  available_filters: string[];
  available_group_by: string[];
}

const FILTERS = ["scope_id", "instance_id"];

export const METRICS: MetricDescriptor[] = [
  { name: "http.rpm", title: "Throughput", unit: "rpm", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "http.response_time", title: "Response time", unit: "ms", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "http.error_rate", title: "Error rate", unit: "%", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "system.cpu_usage_percentage", title: "CPU usage", unit: "%", available_filters: FILTERS, available_group_by: ["instance_id"] },
  { name: "system.memory_usage_percentage", title: "Memory usage percentage", unit: "%", available_filters: FILTERS, available_group_by: ["scope_id", "instance_id"] },
  { name: "system.used_memory_kb", title: "Memory usage in kb", unit: "kb", available_filters: FILTERS, available_group_by: ["scope_id", "instance_id"] },
  { name: "http.healthcheck_count", title: "Healthcheck", unit: "check", available_filters: FILTERS, available_group_by: ["instance_id"] },
];

export const metricList = () => ({ results: METRICS });

const UNITS: Record<string, string> = {
  "http.error_rate": "percent",
  "http.response_time": "seconds",
  "http.rpm": "count_per_minute",
  "http.healthcheck_count": "count",
  "http.healthcheck_fail": "count",
  "system.cpu_usage_percentage": "percent",
  "system.cpu_usage_percentage_by_instance": "percent",
  "system.memory_usage_percentage": "percent",
  "system.used_memory_kb": "kilobytes",
  "cronjob.execution_count": "count",
  "cronjob.success_count": "count",
  "cronjob.failure_count": "count",
  "cronjob.last_execution_start": "timestamp",
  "cronjob.cpu_usage": "percent",
  "cronjob.memory_usage": "bytes",
};

/** Every metric is a gauge; the unit is the bash's, `unknown` for a metric it did not know. */
export const metricConfig = (name: string): { type: "gauge"; unit: string } => ({ type: "gauge", unit: UNITS[name] ?? "unknown" });

/** The HTTP metrics read rates, which need at least five minutes of samples. */
export const isHttpMetric = (name: string): boolean => ["http.error_rate", "http.response_time", "http.rpm", "http.healthcheck_count", "http.healthcheck_fail"].includes(name);
