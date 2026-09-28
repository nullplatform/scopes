#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/list - how LIMIT caps the pod list
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  unset LIMIT APPLICATION_ID SCOPE_ID DEPLOYMENT_ID

  kubectl() {
    jq -n '{items: [range(1; 4) | {
      metadata: {name: "pod-\(.)", namespace: "nullplatform", creationTimestamp: "2025-01-01T00:00:00Z", labels: {}},
      status: {phase: "Running", podIP: "10.0.0.\(.)", containerStatuses: [{image: "app:x86"}]},
      spec: {nodeName: "node-1", containers: [{resources: {requests: {cpu: "100m", memory: "128Mi"}, limits: {cpu: "200m", memory: "256Mi"}}}]}
    }]}'
  }
  export -f kubectl
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
