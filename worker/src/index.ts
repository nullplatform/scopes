import { createPlugin, registerManifest } from "@nullplatform/plugin";

// Dockerized bridge for the classic bash `scopes` repo. In the old model the
// agent ran `./entrypoint --service-path=.../k8s` over the "exec" command type
// with NP_ACTION_CONTEXT in the env. Here the SDK is the gRPC worker the
// orchestrator agent dials, and execute() just re-exports NP_ACTION_CONTEXT and
// shells out to the SAME baked entrypoint — so behavior is identical to before.
//
// Both the entrypoint path and the service-path are hardcoded (baked into the
// image) but overridable via env, so one image can serve k8s (default) and an
// operator can repoint it without a rebuild.
const NAME = "scopes-k8s";
const VERSION = "0.0.1";
const ENTRYPOINT = process.env.NP_SCOPE_ENTRYPOINT ?? "/app/scopes/entrypoint";
const SERVICE_PATH = process.env.NP_SERVICE_PATH ?? "/app/scopes/k8s";
// Optional overrides layered on top of the base service-path. One image can
// then be `FROM nullplatform/scopes:k8s` + a few overridden step files, exactly
// like the bash `scheduled_task` reuses `k8s` via --overrides-path. Comma-
// separated → multiple --overrides-path args (the entrypoint merges them).
const OVERRIDES_PATH = process.env.NP_OVERRIDES_PATH ?? "";

const manifest = {
  name: NAME,
  version: VERSION,
  // The classic entrypoint handles scope + service (deployment) + telemetry
  // (log/metric/instance) actions; it dispatches internally off the action.
  command_types: ["scope", "service", "action"],
  agent: {
    selector: { package: NAME },
    sources: ["service", "telemetry"],
  },
};
registerManifest(manifest);

// Raw createPlugin has no built-in --describe; answer it ourselves so
// `np package publish` can read the manifest.
if (process.argv.includes("--describe")) {
  process.stdout.write(JSON.stringify(manifest));
  process.exit(0);
}

createPlugin({
  async execute(req) {
    // req.payload is the action context — exactly what was NP_ACTION_CONTEXT in
    // the exec model. Re-export it and run the baked bash entrypoint unchanged.
    const ctx = req.payload.toString("utf-8");

    const args = ["bash", ENTRYPOINT, `--service-path=${SERVICE_PATH}`];
    for (const path of OVERRIDES_PATH.split(",").map((s) => s.trim()).filter(Boolean)) {
      args.push(`--overrides-path=${path}`);
    }

    const proc = Bun.spawn(args, {
      env: { ...process.env, NP_ACTION_CONTEXT: ctx },
      stdout: "pipe",
      stderr: "pipe",
    });

    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ]);

    // Stream a copy to the worker's own logs for `kubectl logs` / debugging.
    if (stdout) process.stdout.write(stdout);
    if (stderr) process.stderr.write(stderr);

    const ok = exitCode === 0;
    return {
      success: ok,
      data: { exitCode, stdout, stderr },
      ...(ok ? {} : { error: (stderr || stdout || `entrypoint exited ${exitCode}`).slice(-4000) }),
    };
  },
}).start();
