#!/usr/bin/env bats
# =============================================================================
# Unit tests for scheduled_task scope/trigger - manually trigger the CronJob
#
# Contract:
#   - A scope with no active deployment has no CronJob, so triggering must fail
#     early with a clear "deploy first" message instead of an opaque kubectl
#     error from `kubectl create job --from=cronjob/`.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  # The workflow loads the `log` function via a `load logging` step, so the
  # script assumes it exists. Mock it here (errors go to stderr, like the real one).
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export K8S_NAMESPACE="default-namespace"

  # Base CONTEXT: deployed scope with an active deployment
  export CONTEXT='{
    "scope": {
      "id": "scope-123",
      "current_active_deployment": "deploy-456"
    },
    "providers": {
      "container-orchestration": {
        "cluster": {
          "namespace": "provider-namespace"
        }
      }
    }
  }'

  # Mock kubectl: cronjob exists, job creation succeeds
  kubectl() {
    case "$*" in
      "get cronjob -n provider-namespace -l scope_id=scope-123 -o jsonpath={.items[0].metadata.name}")
        echo "my-cronjob"
        return 0
        ;;
      "create job --from=cronjob/my-cronjob"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  # Deterministic timestamp for job name suffix
  date() { echo "1700000000"; }
  export -f date
}

teardown() {
  unset -f kubectl date log
}

# =============================================================================
# Success Flow
# =============================================================================
@test "trigger: success flow - finds cronjob and triggers a job" {
  run bash "$BATS_TEST_DIRNAME/../trigger"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Triggering job my-cronjob"
  assert_contains "$output" "✅ The job my-cronjob was triggered, you can follow the execution from the logs screen"
}

# =============================================================================
# Error: scope not deployed (no active deployment)
# =============================================================================
@test "trigger: fails with a clear message when the scope has no active deployment" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.scope.current_active_deployment)')

  run bash "$BATS_TEST_DIRNAME/../trigger"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ The scope has no active deployment, so there is no scheduled job to trigger"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The scope has not been deployed yet"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Deploy the scope first, then trigger the job"
}

@test "trigger: fails when current_active_deployment is null" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.current_active_deployment = null')

  run bash "$BATS_TEST_DIRNAME/../trigger"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ The scope has no active deployment, so there is no scheduled job to trigger"
  assert_contains "$output" "• Deploy the scope first, then trigger the job"
}

# =============================================================================
# Error: deployed but no CronJob found
# =============================================================================
@test "trigger: fails with a clear message when no CronJob exists for the scope" {
  kubectl() {
    case "$*" in
      "get cronjob -n provider-namespace -l scope_id=scope-123 -o jsonpath={.items[0].metadata.name}")
        echo ""
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../trigger"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ No CronJob found for scope 'scope-123' in namespace 'provider-namespace'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# Namespace resolution
# =============================================================================
@test "trigger: uses the namespace from the provider for lookup and job creation" {
  # kubectl only succeeds when called against the provider namespace; any other
  # namespace makes it fail, so this asserts the resolved namespace is threaded
  # through both the cronjob lookup and the job creation.
  kubectl() {
    case "$*" in
      "get cronjob -n provider-namespace"*)
        echo "my-cronjob"
        return 0
        ;;
      "create job --from=cronjob/my-cronjob"*"-n provider-namespace")
        return 0
        ;;
      *)
        echo "unexpected namespace: $*" >&2
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../trigger"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ The job my-cronjob was triggered, you can follow the execution from the logs screen"
}

@test "trigger: falls back to the default namespace when the provider namespace is not set" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.namespace)')

  kubectl() {
    case "$*" in
      "get cronjob -n default-namespace"*)
        echo "my-cronjob"
        return 0
        ;;
      "create job --from=cronjob/my-cronjob"*"-n default-namespace")
        return 0
        ;;
      *)
        echo "unexpected namespace: $*" >&2
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../trigger"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ The job my-cronjob was triggered, you can follow the execution from the logs screen"
}

# The workflow includes values.yaml to set K8S_NAMESPACE, but the script also
# guards the expansion so that a missing include can never abort it under
# `set -u`. These reproduce that unguarded environment (K8S_NAMESPACE unset).
@test "trigger: does not abort under set -u when K8S_NAMESPACE is unset (uses provider namespace)" {
  unset K8S_NAMESPACE

  run bash "$BATS_TEST_DIRNAME/../trigger"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ The job my-cronjob was triggered, you can follow the execution from the logs screen"
}

@test "trigger: falls back to the nullplatform default when K8S_NAMESPACE is unset and the provider namespace is absent" {
  unset K8S_NAMESPACE
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.namespace)')

  kubectl() {
    case "$*" in
      "get cronjob -n nullplatform"*)
        echo "my-cronjob"
        return 0
        ;;
      "create job --from=cronjob/my-cronjob"*"-n nullplatform")
        return 0
        ;;
      *)
        echo "unexpected namespace: $*" >&2
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../trigger"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✅ The job my-cronjob was triggered, you can follow the execution from the logs screen"
}

# =============================================================================
# Workflow wiring (trigger-job.yaml) — the layer the script tests can't see
# =============================================================================
@test "trigger-job workflow includes values.yaml so K8S_NAMESPACE is provided" {
  run grep -A2 "^include:" "$BATS_TEST_DIRNAME/../workflows/trigger-job.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "values.yaml"
}

@test "trigger-job workflow loads the log function before the trigger step" {
  run cat "$BATS_TEST_DIRNAME/../workflows/trigger-job.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "name: load logging"
  assert_contains "$output" "\$OVERRIDES_PATH/logging"
}
