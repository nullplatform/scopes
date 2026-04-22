#!/usr/bin/env bats
# =============================================================================
# Unit tests for kubectl_logs - read-only, non-streaming kubectl logs wrapper
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCRIPT="$PROJECT_ROOT/k8s/kubectl_logs"
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
@test "kubectl_logs: shows usage and exits 1 when no args provided" {
  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Usage:"
  assert_contains "$output" "kubectl logs"
}

# =============================================================================
# Hardcoded verb: only 'logs' can be invoked
# =============================================================================
@test "kubectl_logs: invokes kubectl with 'logs' verb followed by user args" {
  run bash "$SCRIPT" my-pod -c my-container

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: logs my-pod -c my-container"
}

@test "kubectl_logs: passes --tail / --since / --previous through unchanged" {
  run bash "$SCRIPT" my-pod --tail 200 --since 1h --previous

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: logs my-pod --tail 200 --since 1h --previous"
}

# =============================================================================
# Default namespace injection
# =============================================================================
@test "kubectl_logs: injects K8S_NAMESPACE when no namespace flag provided" {
  run bash "$SCRIPT" my-pod

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: logs my-pod -n default-ns"
}

@test "kubectl_logs: does not inject namespace when -n is provided" {
  run bash "$SCRIPT" my-pod -n kube-system

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: logs my-pod -n kube-system"
  [[ "$output" != *"-n default-ns"* ]]
}

@test "kubectl_logs: does not inject namespace when --namespace is provided" {
  run bash "$SCRIPT" my-pod --namespace kube-system

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: logs my-pod --namespace kube-system"
  [[ "$output" != *"-n default-ns"* ]]
}

@test "kubectl_logs: does not inject namespace when --namespace=value form is provided" {
  run bash "$SCRIPT" my-pod --namespace=kube-system

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: logs my-pod --namespace=kube-system"
  [[ "$output" != *"-n default-ns"* ]]
}

@test "kubectl_logs: does not inject namespace when K8S_NAMESPACE is unset" {
  unset K8S_NAMESPACE

  run bash "$SCRIPT" my-pod

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: logs my-pod"
  [[ "$output" != *"-n "* ]]
}

# =============================================================================
# Streaming flags are blocked
# =============================================================================
@test "kubectl_logs: rejects -f (would stream)" {
  run bash "$SCRIPT" my-pod -f

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '-f'"
}

@test "kubectl_logs: rejects --follow (would stream)" {
  run bash "$SCRIPT" my-pod --follow

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--follow'"
}

@test "kubectl_logs: rejects --follow=true (would stream)" {
  run bash "$SCRIPT" my-pod --follow=true

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--follow=true'"
}

@test "kubectl_logs: rejects --follow=false too (simpler to block the flag entirely)" {
  run bash "$SCRIPT" my-pod --follow=false

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--follow=false'"
}

# =============================================================================
# Blocked auth/context flags
# =============================================================================
@test "kubectl_logs: rejects --server" {
  run bash "$SCRIPT" my-pod --server https://evil.example.com

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--server'"
}

@test "kubectl_logs: rejects --server=value form" {
  run bash "$SCRIPT" my-pod --server=https://evil.example.com

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--server=https://evil.example.com'"
}

@test "kubectl_logs: rejects --kubeconfig" {
  run bash "$SCRIPT" my-pod --kubeconfig /tmp/evil.yaml

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--kubeconfig'"
}

@test "kubectl_logs: rejects --token" {
  run bash "$SCRIPT" my-pod --token abc123

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--token'"
}

@test "kubectl_logs: rejects --as (impersonation)" {
  run bash "$SCRIPT" my-pod --as cluster-admin

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--as'"
}

@test "kubectl_logs: rejects --as-group" {
  run bash "$SCRIPT" my-pod --as-group system:masters

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--as-group'"
}

@test "kubectl_logs: rejects --context" {
  run bash "$SCRIPT" my-pod --context other-cluster

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--context'"
}

@test "kubectl_logs: rejects --insecure-skip-tls-verify" {
  run bash "$SCRIPT" my-pod --insecure-skip-tls-verify

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--insecure-skip-tls-verify'"
}

@test "kubectl_logs: blocked flag in middle of args is still detected" {
  run bash "$SCRIPT" my-pod -n my-ns --token abc123 --tail 100

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '--token'"
}

@test "kubectl_logs: blocked streaming flag in middle of args is still detected" {
  run bash "$SCRIPT" my-pod --tail 100 -f --timestamps

  [ "$status" -eq 1 ]
  assert_contains "$output" "Refusing argument '-f'"
}

# =============================================================================
# Shell injection safety
# =============================================================================
@test "kubectl_logs: passes args verbatim — no shell interpretation of metachars" {
  # If any of these metachars were interpreted by a shell, kubectl would
  # never see them as part of a single arg. Mock echoes args back as-is.
  run bash "$SCRIPT" -l 'app=foo;bar|baz`whoami`'

  [ "$status" -eq 0 ]
  assert_contains "$output" "kubectl-called: logs -l app=foo;bar|baz\`whoami\` -n default-ns"
}

# =============================================================================
# Exit code propagation
# =============================================================================
@test "kubectl_logs: propagates kubectl exit code on failure" {
  kubectl() {
    echo "Error from server (NotFound): pods 'foo' not found" >&2
    return 1
  }
  export -f kubectl

  run bash "$SCRIPT" foo

  [ "$status" -eq 1 ]
}
