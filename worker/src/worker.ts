/**
 * The worker of a scope image: what the agent dials. It answers the telemetry
 * actions on the cluster itself (telemetry.ts) and runs the repo's bash
 * entrypoint for everything else (bash.ts), the scope actions, the parameters
 * and whatever an overlay took over, so an image built on this needs no
 * worker-bridge. Nothing runs on import: src/index.ts runs it with the real
 * ports, the tests with in-memory ones.
 */

import { ActionError, definePlugin, type Context, type Payload, type Route } from "@nullplatform/plugin";
import { failureOf, runEntrypoint, type Entrypoint } from "./bash";
import startInitialSample from "./samples/start-initial.json" with { type: "json" };
import { telemetryRoutes, type TelemetryConfig, type TelemetryPorts } from "./telemetry";

export interface WorkerConfig extends Omit<TelemetryConfig, "overridesPaths"> {
  /** What the image is to the agent: the package the pin names, and its version. */
  package: { name: string; version: string };
  /** The notification sources the agent routes to this worker. */
  sources: string[];
  entrypoint: Entrypoint;
}

/** The document the agent delivers a payload in, as NP_ACTION_CONTEXT carried it under exec. */
export const documentOf = (payload: Payload): string => JSON.stringify({ notification: payload });

/** The route every other action takes: the bash entrypoint, its output the answer, a non-zero exit the failure. */
export function bashRoute(entrypoint: Entrypoint): Route {
  return {
    name: "bash",
    match: () => true,
    output: () => "raw" as const,
    sample: startInitialSample.notification,
    handler: async (payload: Payload, context: Context) => {
      const run = await runEntrypoint(entrypoint, documentOf(payload), { log: context.log, signal: context.signal });
      if (run.exitCode !== 0) {
        throw new ActionError("ENTRYPOINT_FAILED", failureOf(run));
      }
      return run;
    },
  };
}

export function scopeWorker(config: WorkerConfig, ports: TelemetryPorts) {
  return definePlugin({
    package: { name: config.package.name, version: config.package.version, description: "The scope's worker: telemetry from the cluster, every other action by the bash entrypoint" },
    agent: { sources: config.sources },
    routes: [...telemetryRoutes({ ...config, overridesPaths: config.entrypoint.overridesPaths }, ports), bashRoute(config.entrypoint)],
  });
}
