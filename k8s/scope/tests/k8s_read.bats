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
  unset KUBECTL_FAIL KUBECTL_BIG_OUTPUT NP_EXIT_CODE K8S_READ_MAX_BYTES K8S_READ_ALLOWED_NAMESPACES
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

# =============================================================================
# Flag allowlist
# =============================================================================
@test "k8s_read: refuses -s (would send the agent credentials to another server)" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-s", "https://evil.example"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-s' is not allowed for 'get'"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses -s with the value attached" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-shttps://evil.example"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-shttps://evil.example' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses --server=value" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "--server=https://evil.example"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '--server=https://evil.example' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses --raw" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["--raw", "/api/v1/secrets"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '--raw' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses -f (would read a local manifest and skip the secret filter)" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["-f", "/tmp/x.yaml"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-f' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses --profile-output (would write a file)" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "--profile=cpu", "--profile-output=/tmp/x"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '--profile=cpu' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses --kubeconfig" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "--kubeconfig", "/tmp/k"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '--kubeconfig' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses a watch" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-w"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-w' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses -f on logs (would stream)" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "logs", "args": ["my-pod", "-f"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-f' is not allowed for 'logs'"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses the -- separator" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "--", "-s"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '--' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses a short flag with its value attached" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-nkube-system"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-nkube-system' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses a flag that takes a value when none follows" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-l"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-l' needs a value"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses a flag as the value of another flag" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-l", "-s"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-l' needs a value"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses an output format that reads a local file" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-o", "go-template-file=/var/run/secrets/kubernetes.io/serviceaccount/token"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Output format 'go-template-file=/var/run/secrets/kubernetes.io/serviceaccount/token' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses --output=jsonpath-file" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "--output=jsonpath-file=/etc/passwd"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Output format 'jsonpath-file=/etc/passwd' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: allows the listed get flags" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-l", "app=a", "-o", "jsonpath={.items[*].metadata.name}", "--sort-by=.metadata.name", "--no-headers"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "[--sort-by=.metadata.name] [--no-headers]"
}

@test "k8s_read: allows the listed logs flags" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "logs", "args": ["my-pod", "-c", "application", "--tail=100", "--since=1h", "--previous", "--timestamps"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "[--previous] [--timestamps]"
}

# =============================================================================
# Namespaces
# =============================================================================
@test "k8s_read: refuses another namespace by default" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-n", "kube-system"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Namespace 'kube-system' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses another namespace in --namespace=value form" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "--namespace=kube-system"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Namespace 'kube-system' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses -A by default" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-A"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '-A' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses a namespace outside the allowed list" {
  export K8S_READ_ALLOWED_NAMESPACES="kube-system, istio-system"
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-n", "default"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Namespace 'default' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: refuses -A when the allowed list names namespaces" {
  export K8S_READ_ALLOWED_NAMESPACES="kube-system"
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "--all-namespaces"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Flag '--all-namespaces' is not allowed"
  [ ! -f "$NP_CALL" ]
}

@test "k8s_read: allows the scope namespace when given explicitly" {
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-n", "provider-namespace"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "kubectl-called: [get] [pods] [-n] [provider-namespace]"
}

@test "k8s_read: allows a namespace in the allowed list" {
  export K8S_READ_ALLOWED_NAMESPACES="kube-system, istio-system"
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "logs", "args": ["istiod-abc", "-n", "istio-system"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "kubectl-called: [logs] [istiod-abc] [-n] [istio-system]"
}

@test "k8s_read: allows any namespace and -A with a wildcard" {
  export K8S_READ_ALLOWED_NAMESPACES="*"
  export NP_ACTION_CONTEXT=$(action_context '{"scope_id": 123, "command": "get", "args": ["pods", "-A"]}')

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$(jq -r '.results.output' "$BODY_COPY")" "kubectl-called: [get] [pods] [-A]"
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
