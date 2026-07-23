#!/usr/bin/env bats
# =============================================================================
# Unit tests for scheduled_task/deployment/wait_job - wait for a run-once Job.
#
# Contract:
#   - Scheduled (CronJob) deployments have nothing to complete: the script is a
#     no-op and exits 0 without touching kubectl.
#   - Run-once deployments wait for the Job named job-$SCOPE_ID-$DEPLOYMENT_ID to
#     reach Complete (exit 0) or Failed/timeout (exit 1, with actionable logs).
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  # The workflow loads `log` via a `load logging` step; the script assumes it
  # exists. Mock it here (errors go to stderr, like the real one).
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  # No real waiting in tests.
  sleep() { :; }
  export -f sleep

  export K8S_NAMESPACE="default-namespace"
  export JOB_WAIT_TIMEOUT=30

  # Base CONTEXT: a run-once, deployed scope.
  export CONTEXT='{
    "scope": {
      "id": "scope-123",
      "capabilities": { "cron": "run-once" }
    },
    "deployment": { "id": "deploy-456" },
    "providers": {
      "container-orchestration": {
        "cluster": { "namespace": "provider-namespace" }
      }
    }
  }'

  # Default kubectl mock: the Job is Complete.
  kubectl() {
    case "$*" in
      "get job job-scope-123-deploy-456 -n provider-namespace -o json")
        echo '{"status":{"conditions":[{"type":"Complete","status":"True"}]}}'
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl
}

teardown() {
  unset -f kubectl log sleep
}

# =============================================================================
# No-op for scheduled (CronJob) deployments
# =============================================================================
@test "wait_job: scheduled mode is a no-op and never calls kubectl" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.cron = "*/5 * * * *"')

  # Any kubectl call would be a bug in this path.
  kubectl() { echo "kubectl must not be called: $*" >&2; return 1; }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_job"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Not a run-once deployment (cron='*/5 * * * *'), nothing to wait for"
}

# =============================================================================
# Success: Job completes
# =============================================================================
@test "wait_job: run-once success - waits for the Job to complete" {
  run bash "$BATS_TEST_DIRNAME/../wait_job"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Waiting for job job-scope-123-deploy-456 to complete (timeout 30s)"
  assert_contains "$output" "✅ Job job-scope-123-deploy-456 completed successfully"
}

# =============================================================================
# Failure: Job fails
# =============================================================================
@test "wait_job: run-once failure - exits 1 with the Job failure reason" {
  kubectl() {
    case "$*" in
      "get job job-scope-123-deploy-456 -n provider-namespace -o json")
        echo '{"status":{"conditions":[{"type":"Failed","status":"True","message":"BackoffLimitExceeded"}]}}'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_job"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Job job-scope-123-deploy-456 failed: BackoffLimitExceeded"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Inspect the failed run from the logs screen"
}

# =============================================================================
# Timeout: Job never reaches a terminal condition
# =============================================================================
@test "wait_job: run-once timeout - exits 1 when the Job never completes" {
  export JOB_WAIT_TIMEOUT=5  # -> MAX_ITERATIONS = 1

  kubectl() {
    case "$*" in
      "get job job-scope-123-deploy-456 -n provider-namespace -o json")
        echo '{"status":{}}'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_job"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Timeout waiting for job job-scope-123-deploy-456 to complete after 5s"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Raise JOB_WAIT_TIMEOUT in the scope configuration if the task legitimately needs more time"
}

# =============================================================================
# Namespace resolution / set -u guard
# =============================================================================
@test "wait_job: resolves the namespace from the provider" {
  # kubectl only answers for the provider namespace; any other namespace fails.
  kubectl() {
    case "$*" in
      "get job job-scope-123-deploy-456 -n provider-namespace -o json")
        echo '{"status":{"conditions":[{"type":"Complete","status":"True"}]}}'
        return 0
        ;;
      *) echo "unexpected namespace: $*" >&2; return 1 ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_job"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Job job-scope-123-deploy-456 completed successfully"
}

@test "wait_job: does not abort under set -u when K8S_NAMESPACE is unset" {
  unset K8S_NAMESPACE

  run bash "$BATS_TEST_DIRNAME/../wait_job"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ Job job-scope-123-deploy-456 completed successfully"
}

# =============================================================================
# Workflow wiring — the deploy workflows must run wait_job in place of the
# base "wait deployment active" step, on both the initial and blue-green paths.
# A missing wiring here silently drops the run-once completion wait.
# =============================================================================
@test "initial workflow replaces 'wait deployment active' with wait_job after apply" {
  run python3 - "$BATS_TEST_DIRNAME/../workflows/initial.yaml" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
apply = next(s for s in wf["steps"] if s.get("name") == "apply")
post = apply["post"]
assert post["name"] == "wait deployment active", post
assert post["action"] == "replace", post
assert post["file"] == "$OVERRIDES_PATH/deployment/wait_job", post
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"
}

@test "blue_green workflow replaces 'wait deployment active' with wait_job after apply" {
  run python3 - "$BATS_TEST_DIRNAME/../workflows/blue_green.yaml" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
apply = next(s for s in wf["steps"] if s.get("name") == "apply")
post = apply["post"]
assert post["name"] == "wait deployment active", post
assert post["action"] == "replace", post
assert post["file"] == "$OVERRIDES_PATH/deployment/wait_job", post
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"
}
