#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/list - LIMIT and which container the details come from
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  unset LIMIT APPLICATION_ID SCOPE_ID DEPLOYMENT_ID

  kubectl() {
    jq -n '{items: [range(1; 4) | {
      metadata: {name: "pod-\(.)", namespace: "nullplatform", creationTimestamp: "2025-01-01T00:00:00Z", labels: {}},
      status: {phase: "Running", podIP: "10.0.0.\(.)", containerStatuses: [
        {name: "http", image: "traffic-manager:1.7.0-x86"},
        {name: "application", image: "app:1.0.0-arm64"}
      ]},
      spec: {nodeName: "node-1", containers: [
        {name: "http", resources: {requests: {cpu: "31m"}, limits: {cpu: "2000m", memory: "1024Mi"}}},
        {name: "application", resources: {requests: {cpu: "100m", memory: "128Mi"}, limits: {cpu: "200m", memory: "256Mi"}}}
      ]}
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

@test "cpu is reported from the application container, not the traffic sidecar" {
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.results[0].details.cpu.requested')" = "0.1" ]
  [ "$(echo "$output" | jq -r '.results[0].details.cpu.limit')" = "0.2" ]
}

@test "memory is reported from the application container, not the traffic sidecar" {
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.results[0].details.memory.requested')" = "128Mi" ]
  [ "$(echo "$output" | jq -r '.results[0].details.memory.limit')" = "256Mi" ]
}

@test "architecture is read from the application container image" {
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.results[0].details.architecture')" = "arm64" ]
}

@test "the application container is found whatever its position among extra containers" {
  kubectl() {
    jq -n '{items: [{
      metadata: {name: "pod-1", namespace: "nullplatform", creationTimestamp: "2025-01-01T00:00:00Z", labels: {}},
      status: {phase: "Running", podIP: "10.0.0.1", containerStatuses: [
        {name: "http", image: "traffic-manager:1.7.0-x86"},
        {name: "application", image: "app:1.0.0-arm64"},
        {name: "sidecar-custom", image: "vendor-agent:x86"}
      ]},
      spec: {nodeName: "node-1", containers: [
        {name: "http", resources: {requests: {cpu: "31m"}, limits: {cpu: "2000m", memory: "1024Mi"}}},
        {name: "application", resources: {requests: {cpu: "500m", memory: "512Mi"}, limits: {cpu: "1000m", memory: "1024Mi"}}},
        {name: "sidecar-custom", resources: {requests: {cpu: "10m", memory: "64Mi"}, limits: {cpu: "20m", memory: "64Mi"}}}
      ]}
    }]}'
  }
  export -f kubectl
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.results[0].details.cpu.requested')" = "0.5" ]
  [ "$(echo "$output" | jq -r '.results[0].details.memory.requested')" = "512Mi" ]
  [ "$(echo "$output" | jq -r '.results[0].details.architecture')" = "arm64" ]
}

@test "a pod with no application container falls back to the first container" {
  kubectl() {
    jq -n '{items: [{
      metadata: {name: "pod-1", namespace: "nullplatform", creationTimestamp: "2025-01-01T00:00:00Z", labels: {}},
      status: {phase: "Running", podIP: "10.0.0.1", containerStatuses: [{name: "worker", image: "worker:1.0.0-x86"}]},
      spec: {nodeName: "node-1", containers: [
        {name: "worker", resources: {requests: {cpu: "250m", memory: "64Mi"}, limits: {cpu: "300m", memory: "128Mi"}}}
      ]}
    }]}'
  }
  export -f kubectl
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.results[0].details.cpu.requested')" = "0.25" ]
  [ "$(echo "$output" | jq -r '.results[0].details.memory.limit')" = "128Mi" ]
  [ "$(echo "$output" | jq -r '.results[0].details.architecture')" = "x86" ]
}

@test "a pod whose containers report no resources yields zeroed details" {
  kubectl() {
    jq -n '{items: [{
      metadata: {name: "pod-1", namespace: "nullplatform", creationTimestamp: "2025-01-01T00:00:00Z", labels: {}},
      status: {phase: "Pending"},
      spec: {containers: [{name: "application"}]}
    }]}'
  }
  export -f kubectl
  run bash "$PROJECT_ROOT/k8s/instance/list"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.results[0].details.cpu.requested')" = "0" ]
  [ "$(echo "$output" | jq -r '.results[0].details.memory.requested')" = "0Mi" ]
  [ "$(echo "$output" | jq -r '.results[0].details.ip')" = "pending" ]
}
