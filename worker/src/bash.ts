/**
 * The bash entrypoint, run for one action the way the worker-bridge ran it:
 * `bash <entrypoint> --service-path=<path> [--overrides-path=<path>]…` with the
 * worker's own environment and NP_ACTION_CONTEXT, the document the agent
 * delivered. What it prints is captured for the answer (its stdout is a
 * workflow's output, which the platform reads) and said line by line to the
 * worker's log as it runs, so `kubectl logs` follows an action live. The
 * agent's cancellation ends it.
 */

import type { Logger } from "@nullplatform/plugin";

export interface Entrypoint {
  /** The bash entrypoint the image bakes in. */
  path: string;
  /** The scope's folder, `--service-path`. */
  servicePath: string;
  /** The overlays laid over it, one `--overrides-path` each. */
  overridesPaths: readonly string[];
}

/** What a run of the entrypoint produced. */
export interface EntrypointRun {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** The argv: bash, the entrypoint, its service path, each overrides path. */
export function entrypointArgs(entrypoint: Entrypoint): string[] {
  return ["bash", entrypoint.path, `--service-path=${entrypoint.servicePath}`, ...entrypoint.overridesPaths.map((path) => `--overrides-path=${path}`)];
}

/** The environment: the worker's own, and the document as NP_ACTION_CONTEXT, which nothing overrides. */
export function entrypointEnv(document: string, base: Record<string, string | undefined> = process.env): Record<string, string | undefined> {
  return { ...base, NP_ACTION_CONTEXT: document };
}

/** Reads a stream to its end, saying each line as it completes; `stop` ends the read early, and `text` is what was read. */
function drain(stream: ReadableStream<Uint8Array>, say: (line: string) => void): { text: Promise<string>; stop(): void } {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  const text = (async (): Promise<string> => {
    let whole = "";
    let pending = "";
    for (;;) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      const piece = decoder.decode(value, { stream: true });
      whole += piece;
      pending += piece;
      const lines = pending.split("\n");
      pending = lines.pop() ?? "";
      for (const line of lines) {
        if (line !== "") {
          say(line);
        }
      }
    }
    if (pending !== "") {
      say(pending);
    }
    return whole;
  })();
  return {
    text,
    stop: () => {
      reader.cancel().catch(() => undefined);
    },
  };
}

export interface RunOptions {
  /** The worker's log, where the entrypoint's lines go as they come. */
  log: Logger;
  /** The agent's cancellation: the entrypoint is told to stop. */
  signal?: AbortSignal;
}

/**
 * Runs the entrypoint for one action and captures what it printed. A cancelled
 * action has the entrypoint told to stop; what it left running behind it may
 * hold its pipes, so the read ends with the entrypoint, not with them.
 */
export async function runEntrypoint(entrypoint: Entrypoint, document: string, options: RunOptions): Promise<EntrypointRun> {
  const child = Bun.spawn(entrypointArgs(entrypoint), { env: entrypointEnv(document), stdout: "pipe", stderr: "pipe" });
  const stdout = drain(child.stdout, (line) => options.log.info(line));
  const stderr = drain(child.stderr, (line) => options.log.warn(line));
  const stop = (): void => {
    child.kill("SIGTERM");
  };
  options.signal?.addEventListener("abort", stop, { once: true });
  try {
    const exitCode = await child.exited;
    if (options.signal?.aborted) {
      stdout.stop();
      stderr.stop();
    }
    return { exitCode, stdout: await stdout.text, stderr: await stderr.text };
  } finally {
    options.signal?.removeEventListener("abort", stop);
  }
}

/** Why a run failed, for the answer: the last of what it printed, its exit code when it printed nothing. */
export function failureOf(run: EntrypointRun): string {
  return (run.stderr || run.stdout || `the entrypoint exited ${run.exitCode}`).slice(-4000);
}
