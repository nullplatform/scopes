# scopes — Project Notes

## Tracing

Workflows report their progress to the tracing API and the dashboard draws the
story from it. This covers every scope implementation here (k8s, azure,
azure-aro, onprem, scheduled_task, service, and any added later), not just k8s.

1. **MUST evaluate tracing on every change — no exceptions, no matter how
   small.** Before writing code, decide whether the trace needs adding or
   modifying: a step added, removed, renamed or regrouped, a wait added or
   lengthened, a new way to fail, a change in what an operation produces. Do
   not skip this because the change "is not about tracing". The PR description
   MUST carry a `Tracing:` line — `unchanged`, or what was added or modified —
   and a PR without it is not done.
2. **MUST read `vendor/catalog-tracing-sh/llms.txt` BEFORE writing or changing
   any tracing code.** Never trace from memory. The SDK is the submodule at
   `vendor/catalog-tracing-sh` (https://github.com/nullplatform/catalog-tracing-sh)
   and its `llms.txt` is the only authority on using it; if it says something is
   not implemented, it is not available. Run `git submodule update --init` to
   have it, and re-read it when the submodule moves.

Repository conventions on top of the guide:

- Workflow YAML `trace:` block → the scope type's `logging` helpers
  (`np_scope_*`, documented in `k8s/logging`, the reference) → scripts. Scripts
  never call `np_trace_*` and never guard a helper (`|| true`, `if`, `set +e`);
  guards live in the helper layer, so an untraced run stays byte-identical.
- `scheduled_task/logging` is a byte-for-byte copy of `k8s/logging`.
- A workflow not traced yet is brought to the bar when changed; a new scope
  type ships traced. Changing steps or groups changes the job's plan: say so.
- Verify with `bats k8s/utils/tests/trace_logging.bats` and the scope type's
  workflow suites, then read the story in the dashboard.
