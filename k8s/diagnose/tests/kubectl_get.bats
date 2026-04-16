#!/usr/bin/env bats
# =============================================================================
# Unit tests for kubectl_get - read-only kubectl wrapper for troubleshooting
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCRIPT="$PROJECT_ROOT/k8s/kubectl_get"
  export K8S_NAMESPACE="default-ns"

  # Mock kubectl: echo back what was received so tests can assert the args.
  kubectl() {
    echo "kubectl-called: $*"
    return 0
  }
  export -f kubectl
}

teardown() {
  unset -f kubectl log
  unset K8S_NAMESPACE SCRIPT PROJECT_ROOT
}

# =============================================================================
# Usage
# =============================================================================
@test "kubectl_get: shows usage and exits 1 when no args provided" {
  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Usage:"
  assert_contains "$output" "kubectl get"
}

# =============================================================================
# Hardcoded verb: only 'get' can be invoked
# =============================================================================
@test "kubectl_get: invokes kubectl with 'get' verb followed by user args" {
  run bash "$SCRIPT" pods -o wide

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods -o wide"
}

# =============================================================================
# Default namespace injection
# =============================================================================
@test "kubectl_get: injects K8S_NAMESPACE when no namespace flag provided" {
  run bash "$SCRIPT" pods

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods -n default-ns"
}

@test "kubectl_get: does not inject namespace when -n is provided" {
  run bash "$SCRIPT" pods -n kube-system

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods -n kube-system"
  [[ "$output" != *"-n default-ns"* ]]
}

@test "kubectl_get: does not inject namespace when --namespace is provided" {
  run bash "$SCRIPT" pods --namespace kube-system

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods --namespace kube-system"
  [[ "$output" != *"-n default-ns"* ]]
}

@test "kubectl_get: does not inject namespace when --namespace=value form is provided" {
  run bash "$SCRIPT" pods --namespace=kube-system

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods --namespace=kube-system"
  [[ "$output" != *"-n default-ns"* ]]
}

@test "kubectl_get: does not inject namespace when -A is provided" {
  run bash "$SCRIPT" pods -A

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods -A"
  [[ "$output" != *"-n default-ns"* ]]
}

@test "kubectl_get: does not inject namespace when --all-namespaces is provided" {
  run bash "$SCRIPT" pods --all-namespaces

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods --all-namespaces"
  [[ "$output" != *"-n default-ns"* ]]
}

@test "kubectl_get: does not inject namespace when K8S_NAMESPACE is unset" {
  unset K8S_NAMESPACE

  run bash "$SCRIPT" pods

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods"
  [[ "$output" != *"-n "* ]]
}

# =============================================================================
# Blocked flags
# =============================================================================
@test "kubectl_get: rejects --server" {
  run bash "$SCRIPT" pods --server https://evil.example.com

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--server'"
}

@test "kubectl_get: rejects --server=value form" {
  run bash "$SCRIPT" pods --server=https://evil.example.com

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--server=https://evil.example.com'"
}

@test "kubectl_get: rejects --kubeconfig" {
  run bash "$SCRIPT" pods --kubeconfig /tmp/evil.yaml

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--kubeconfig'"
}

@test "kubectl_get: rejects --token" {
  run bash "$SCRIPT" pods --token abc123

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--token'"
}

@test "kubectl_get: rejects --as (impersonation)" {
  run bash "$SCRIPT" pods --as cluster-admin

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--as'"
}

@test "kubectl_get: rejects --as-group" {
  run bash "$SCRIPT" pods --as-group system:masters

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--as-group'"
}

@test "kubectl_get: rejects --context" {
  run bash "$SCRIPT" pods --context other-cluster

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--context'"
}

@test "kubectl_get: rejects --insecure-skip-tls-verify" {
  run bash "$SCRIPT" pods --insecure-skip-tls-verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--insecure-skip-tls-verify'"
}

@test "kubectl_get: rejects -w (avoid hangs)" {
  run bash "$SCRIPT" pods -w

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '-w'"
}

@test "kubectl_get: rejects --watch" {
  run bash "$SCRIPT" pods --watch

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--watch'"
}

@test "kubectl_get: blocked flag in middle of args is still detected" {
  run bash "$SCRIPT" pods -n my-ns --token abc123 -o yaml

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--token'"
}

# =============================================================================
# Shell injection safety
# =============================================================================
@test "kubectl_get: passes args verbatim — no shell interpretation of metachars" {
  # If any of these metachars were interpreted by a shell, kubectl would
  # never see them as part of a single arg. Mock echoes args back as-is.
  run bash "$SCRIPT" pods -l 'app=foo;bar|baz`whoami`'

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: get pods -l app=foo;bar|baz\`whoami\` -n default-ns"
}

# =============================================================================
# Exit code propagation
# =============================================================================
@test "kubectl_get: propagates kubectl exit code on failure" {
  kubectl() {
    echo "Error from server (NotFound): pods 'foo' not found" >&2
    return 1
  }
  export -f kubectl

  run bash "$SCRIPT" pods foo

  [ "$status" -eq 1 ]
}

# =============================================================================
# Secret content stripping
# =============================================================================
# Mock that returns realistic secret JSON when invoked with secret + -o json.
mock_kubectl_with_secrets() {
  kubectl() {
    if [[ "$*" == *"secret"* && "$*" == *"-o json"* ]]; then
      # Single secret (when name is in args) returns object; otherwise list.
      if [[ "$*" == *"secret foo"* || "$*" == *"secret/foo"* ]]; then
        cat <<'EOF'
{
  "metadata": {"name": "foo", "namespace": "default-ns"},
  "type": "Opaque",
  "data": {"password": "c3VwZXJzZWNyZXQ="},
  "stringData": {"plain": "alsosecret"}
}
EOF
      else
        cat <<'EOF'
{
  "items": [
    {
      "metadata": {"name": "foo", "namespace": "default-ns"},
      "type": "Opaque",
      "data": {"password": "c3VwZXJzZWNyZXQ="},
      "stringData": {"plain": "alsosecret"}
    }
  ]
}
EOF
      fi
      return 0
    fi
    echo "kubectl-called: $*"
  }
  export -f kubectl
}

@test "kubectl_get: strips .data and .stringData from secret list output" {
  mock_kubectl_with_secrets

  run bash "$SCRIPT" secrets

  [ "$status" -eq 0 ]
  # Metadata still present
  assert_contains "$output" "\"name\": \"foo\""
  assert_contains "$output" "\"type\": \"Opaque\""
  # Sensitive content gone
  [[ "$output" != *"c3VwZXJzZWNyZXQ="* ]]
  [[ "$output" != *"alsosecret"* ]]
  [[ "$output" != *"\"data\""* ]]
  [[ "$output" != *"\"stringData\""* ]]
}

@test "kubectl_get: strips .data and .stringData from single secret output" {
  mock_kubectl_with_secrets

  run bash "$SCRIPT" secret foo

  [ "$status" -eq 0 ]
  assert_contains "$output" "\"name\": \"foo\""
  [[ "$output" != *"c3VwZXJzZWNyZXQ="* ]]
  [[ "$output" != *"alsosecret"* ]]
  [[ "$output" != *"\"data\""* ]]
}

@test "kubectl_get: works for 'secret' (singular) resource name" {
  mock_kubectl_with_secrets

  run bash "$SCRIPT" secret

  [ "$status" -eq 0 ]
  [[ "$output" != *"c3VwZXJzZWNyZXQ="* ]]
}

@test "kubectl_get: works for secret/name slash form" {
  mock_kubectl_with_secrets

  run bash "$SCRIPT" secret/foo

  [ "$status" -eq 0 ]
  [[ "$output" != *"c3VwZXJzZWNyZXQ="* ]]
}

@test "kubectl_get: works for secret,configmap comma form" {
  mock_kubectl_with_secrets

  run bash "$SCRIPT" secret,configmap

  [ "$status" -eq 0 ]
  [[ "$output" != *"c3VwZXJzZWNyZXQ="* ]]
}

@test "kubectl_get: forces -o json when user requested -o yaml on secrets" {
  mock_kubectl_with_secrets

  run bash "$SCRIPT" secrets -o yaml

  [ "$status" -eq 0 ]
  assert_contains "$output" "Output forced to JSON"
  [[ "$output" != *"c3VwZXJzZWNyZXQ="* ]]
}

@test "kubectl_get: rejects -o jsonpath on secrets" {
  run bash "$SCRIPT" secrets -o "jsonpath={.items[*].data.password}"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing -o"
  assert_contains "$output" "jsonpath"
}

@test "kubectl_get: rejects -o go-template on secrets" {
  run bash "$SCRIPT" secrets -o "go-template={{.items}}"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing -o"
  assert_contains "$output" "go-template"
}

@test "kubectl_get: rejects -o custom-columns on secrets" {
  run bash "$SCRIPT" secrets -o "custom-columns=NAME:.metadata.name,DATA:.data"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing -o"
  assert_contains "$output" "custom-columns"
}

@test "kubectl_get: rejects --output=jsonpath= on secrets" {
  run bash "$SCRIPT" secrets --output="jsonpath={.items[*].data}"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing -o"
}

@test "kubectl_get: secret filtering does not affect non-secret resources" {
  mock_kubectl_with_secrets

  run bash "$SCRIPT" pods -o yaml

  [ "$status" -eq 0 ]
  # Goes through the normal (non-filtered) path: mock echoes args.
  assert_contains "$output" "kubectl-called: get pods -o yaml -n default-ns"
}

@test "kubectl_get: propagates kubectl failure exit code through jq pipe" {
  kubectl() {
    echo "Error from server (Forbidden)" >&2
    return 1
  }
  export -f kubectl

  run bash "$SCRIPT" secrets

  [ "$status" -eq 1 ]
}
