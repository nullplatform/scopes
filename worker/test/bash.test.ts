import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { entrypointArgs, entrypointEnv, failureOf, runEntrypoint, type Entrypoint } from "../src/bash";

/** A stand-in for the repo's bash entrypoint: it prints what the worker hands it, the way the classic entrypoints read it. */
const dir = mkdtempSync(join(tmpdir(), "scopes-worker-"));
const path = join(dir, "entrypoint");
writeFileSync(
  path,
  `#!/usr/bin/env bash
echo "context=$NP_ACTION_CONTEXT"
echo "args=$*"
echo "note" >&2
if [ "$FAIL" = "1" ]; then echo "boom" >&2; exit 3; fi
if [ "$HANG" = "1" ]; then sleep 30; fi
`,
);
const entrypoint: Entrypoint = { path, servicePath: "/app/pkg/k8s", overridesPaths: ["/app/pkg/datadog"] };
const document = '{"notification":{"action":"service:action:create"}}';
const said = () => {
  const lines: string[] = [];
  const log = { debug: () => undefined, info: (line: string) => lines.push(`info ${line}`), warn: (line: string) => lines.push(`warn ${line}`), error: () => undefined };
  return { lines, log };
};

describe("the entrypoint's command line", () => {
  test("bash, the entrypoint, the service path, one flag per overrides path", () => {
    expect(entrypointArgs(entrypoint)).toEqual(["bash", path, "--service-path=/app/pkg/k8s", "--overrides-path=/app/pkg/datadog"]);
    expect(entrypointArgs({ ...entrypoint, overridesPaths: [] })).toEqual(["bash", path, "--service-path=/app/pkg/k8s"]);
  });

  test("the environment is the worker's with the document as NP_ACTION_CONTEXT, which nothing overrides", () => {
    expect(entrypointEnv(document, { HOME: "/home/app", NP_ACTION_CONTEXT: "stale" })).toEqual({ HOME: "/home/app", NP_ACTION_CONTEXT: document });
  });
});

describe("a run", () => {
  test("hands the entrypoint the document and its arguments, and says each line as it comes", async () => {
    const { lines, log } = said();
    const run = await runEntrypoint(entrypoint, document, { log });
    expect(run.exitCode).toBe(0);
    expect(run.stdout).toContain(`context=${document}`);
    expect(run.stdout).toContain("args=--service-path=/app/pkg/k8s --overrides-path=/app/pkg/datadog");
    expect(lines).toContain(`info context=${document}`);
    expect(lines).toContain("warn note");
  });

  test("a failing entrypoint reports its exit code, and the failure is the last of what it printed", async () => {
    const { log } = said();
    const run = await runEntrypoint(entrypoint, document, { log });
    const broken = await (async () => {
      process.env.FAIL = "1";
      try {
        return await runEntrypoint(entrypoint, document, { log });
      } finally {
        delete process.env.FAIL;
      }
    })();
    expect(run.exitCode).toBe(0);
    expect(broken.exitCode).toBe(3);
    expect(failureOf(broken)).toContain("boom");
    expect(failureOf({ exitCode: 7, stdout: "", stderr: "" })).toBe("the entrypoint exited 7");
  });

  test("the agent's cancellation stops it", async () => {
    const { log } = said();
    const controller = new AbortController();
    process.env.HANG = "1";
    try {
      const running = runEntrypoint(entrypoint, document, { log, signal: controller.signal });
      setTimeout(() => controller.abort(), 200);
      const run = await running;
      expect(run.exitCode).not.toBe(0);
      expect(run.stdout).toContain(`context=${document}`);
    } finally {
      delete process.env.HANG;
    }
  });
});
