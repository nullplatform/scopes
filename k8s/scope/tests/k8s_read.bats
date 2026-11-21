#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/k8s_read - read-only kubectl query stored in the action
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCRIPT="$PROJECT_ROOT/k8s/scope/k8s_read"
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export K8S_NAMESPACE="default-namespace"
  export BODY_COPY="$BATS_TEST_TMPDIR/body.json"
  export NP_CALL="$BATS_TEST_TMPDIR/np_call"

  export CONTEXT='{
    "scope": { "id": "scope-123" },
    "providers": {
      "container-orchestration": { "cluster": { "namespace": "provider-namespace" } }
    }
  }'

  # The wrappers run "kubectl get|logs <args>": echo them back. Every other
  # call (namespace resolution) answers empty.
  kubectl() {
    case "$1" in
      get|logs)
        if [[ " $* " == *" -o json "* && " $* " == *" secrets "* ]]; then
          echo '{"items":[{"metadata":{"name":"s1"},"data":{"password":"c2VjcmV0"}}]}'
        elif [[ " $* " == *" -l scope_id="* ]]; then
          return 0
        elif [[ "${KUBECTL_FAIL:-}" == "true" ]]; then
          echo "Error from server (NotFound): pods \"missing\" not found" >&2
          return 1
        elif [[ -n "${KUBECTL_BIG_OUTPUT:-}" ]]; then
          head -c "$KUBECTL_BIG_OUTPUT" /dev/zero | tr '\0' 'x'
          echo "LAST-LINE"
        else
          printf 'kubectl-called:'; printf ' [%s]' "$@"; echo
        fi
        ;;
      *) return 0 ;;
    esac
  }
  export -f kubectl

  # Mock np: keep the call and a copy of the body file.
  np() {
    echo "$*" > "$NP_CALL"
    local prev=""
    for arg in "$@"; do
      [[ "$prev" == "--body" ]] && cp "$arg" "$BODY_COPY"
      prev="$arg"
    done
    return "${NP_EXIT_CODE:-0}"
  }
  export -f np
}

teardown() {
  unset -f kubectl np log
  unset KUBECTL_FAIL KUBECTL_BIG_OUTPUT NP_EXIT_CODE K8S_READ_MAX_BYTES
}

action_context() {
  jq -nc --argjson parameters "$1" \
    '{notification: {id: "action-1", service: {id: "service-9"}, parameters: $parameters}}'
}

# =============================================================================
# Command selection
# =============================================================================
@test "k8s_read: runs kubectl get with the given args and stores the output" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-o", "wide"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_equal "$(jq -r '.results.exit_code' "$BODY_COPY")" "0"
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "kubectl-called: [get] [pods] [-o] [wide] [-n] [provider-namespace]"
  assert_equal "$(jq -r '.results.truncated' "$BODY_COPY")" "false"
  assert_equal "$(jq -r '.results.namespace' "$BODY_COPY")" "provider-namespace"
}

@test "k8s_read: runs kubectl logs with the given args" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "logs", "args": ["my-pod", "--tail=50"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "kubectl-called: [logs] [my-pod] [--tail=50] [-n] [provider-namespace]"
}

@test "k8s_read: patches the action that triggered it" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$NP_CALL")" "service action patch --id action-1 --serviceId service-9 --body"
}

@test "k8s_read: keeps an argument with spaces as a single argument" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-l", "app in (a, b)"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "[-l] [app in (a, b)]"
}

@test "k8s_read: does not add the scope namespace when the args carry one" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-n", "kube-system"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "kubectl-called: [get] [pods] [-n] [kube-system]"
}

# =============================================================================
# Rejected input
# =============================================================================
@test "k8s_read: rejects a command other than get or logs" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "delete", "args": ["pods", "--all"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Unsupported command 'delete'"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: rejects a missing command" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Unsupported command ''"
}

@test "k8s_read: rejects args that are not an array of strings" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": "pods; rm -rf /"}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "must be an array of strings"
}

@test "k8s_read: a flag blocked by the wrapper fails and is reported in the results" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["--raw", "/api/v1/secrets"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_equal "$(jq -r '.results.exit_code' "$BODY_COPY")" "1"
  assert_contains "$(jq -r '.results.error' "$BODY_COPY")" "Refusing argument '--raw'"
}

# =============================================================================
# Output handling
# =============================================================================
@test "k8s_read: secret values never reach the results" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["secrets"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" '"name": "s1"'
  [[ "$(cat "$BODY_COPY")" != *"c2VjcmV0"* ]]
}

@test "k8s_read: truncates a large output to its last bytes" {
  export K8S_READ_MAX_BYTES=1000
  export KUBECTL_BIG_OUTPUT=5000
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "logs", "args": ["my-pod"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_equal "$(jq -r '.results.truncated' "$BODY_COPY")" "true"
  assert_equal "$(jq -r '.results.output | length' "$BODY_COPY")" "1000"
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "LAST-LINE"
}

@test "k8s_read: a failing kubectl stores its error and fails the action" {
  export KUBECTL_FAIL=true
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "logs", "args": ["missing"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_equal "$(jq -r '.results.exit_code' "$BODY_COPY")" "1"
  assert_contains "$(jq -r '.results.error' "$BODY_COPY")" "NotFound"
}

@test "k8s_read: fails when the results cannot be stored" {
  export NP_EXIT_CODE=1
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Failed to store the output in the action results"
}
