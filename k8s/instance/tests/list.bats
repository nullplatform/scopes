#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/list - how LIMIT caps the pod list
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  unset LIMIT APPLICATION_ID SCOPE_ID DEPLOYMENT_ID
  unset CONTEXT NAMESPACE_OVERRIDE K8S_NAMESPACE

  export KUBECTL_ARGS_FILE="$(mktemp)"

  kubectl() {
    printf '%s\n' "$*" >> "$KUBECTL_ARGS_FILE"
    jq -n '{items: [range(1; 4) | {
      metadata: {name: "pod-\(.)", namespace: "nullplatform", creationTimestamp: "2025-01-01T00:00:00Z", labels: {}},
      status: {phase: "Running", podIP: "10.0.0.\(.)", containerStatuses: [{image: "app:x86"}]},
      spec: {nodeName: "node-1", containers: [{resources: {requests: {cpu: "100m", memory: "128Mi"}, limits: {cpu: "200m", memory: "256Mi"}}}]}
    }]}'
  }
  export -f kubectl
}

teardown() {
  [ -n "$KUBECTL_ARGS_FILE" ] && rm -f "$KUBECTL_ARGS_FILE"
  unset CONTEXT NAMESPACE_OVERRIDE K8S_NAMESPACE KUBECTL_ARGS_FILE 2>/dev/null || true
}

@test "without LIMIT every pod is returned" {
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.results | length')" -eq 3 ]
}

@test "LIMIT caps the list to the first N pods" {
  export LIMIT=2
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.results | length')" -eq 2 ]
  [ "$(echo "$output" | jq -r '.results[0].id')" = "pod-1" ]
}

@test "LIMIT=0 means no cap" {
  export LIMIT=0
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.results | length')" -eq 3 ]
}

# =============================================================================
# Namespace resolution - must match scope/build_context, or the instance list
# (and the per-instance metrics built from it) comes back empty
# =============================================================================
@test "list: falls back to the nullplatform namespace" {
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  grep -q -- "-n nullplatform" "$KUBECTL_ARGS_FILE"
}

@test "list: honors K8S_NAMESPACE from the scope configuration" {
  export K8S_NAMESPACE="apps"
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  grep -q -- "-n apps" "$KUBECTL_ARGS_FILE"
}

@test "list: the container-orchestration provider wins over the environment" {
  export NAMESPACE_OVERRIDE="override"
  export CONTEXT='{"providers":{"container-orchestration":{"cluster":{"namespace":"from-provider"}}}}'
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  grep -q -- "-n from-provider" "$KUBECTL_ARGS_FILE"
}
