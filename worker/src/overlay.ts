/**
 * What an overlay takes over. An image lays overrides paths over the service
 * path (`NP_OVERRIDES_PATH`, comma-separated: the datadog folder, an azure one);
 * the bash entrypoint runs an overlay's workflow in place of the base one when
 * the overlay has it. A telemetry action the worker would answer itself stays
 * the bash's when an overlay provides its workflow, so the datadog image keeps
 * answering metrics from Datadog while logs and instances come from the cluster.
 */

import { existsSync } from "node:fs";
import { join } from "node:path";

/** The workflow each telemetry action runs, relative to a service or overrides path. */
export const TELEMETRY_WORKFLOWS: Readonly<Record<string, string>> = {
  "log:read": "log/workflows/log.yaml",
  "metric:list": "metric/workflows/list.yaml",
  "metric:data": "metric/workflows/metric.yaml",
  "instance:data": "instance/workflows/list.yaml",
};

/** The overlay workflow that answers `action`, when one of `overridesPaths` provides it. */
export function overlayWorkflow(action: string, overridesPaths: readonly string[], exists: (path: string) => boolean = existsSync): string | undefined {
  const relative = TELEMETRY_WORKFLOWS[action];
  if (relative === undefined) {
    return undefined;
  }
  return overridesPaths.map((path) => join(path, relative)).find(exists);
}
