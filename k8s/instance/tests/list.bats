#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/list - list instances/pods with details
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$BATS_TEST_DIRNAME/../list"

  export NAMESPACE_OVERRIDE=""
  export APPLICATION_ID="app-123"
  export SCOPE_ID="scope-456"
  export DEPLOYMENT_ID="deploy-789"
  export LIMIT=10

  # Default kubectl mock — two pods with different characteristics
  kubectl() {
    echo '{
      "items": [
        {
          "metadata": {
            "name": "app-pod-1",
            "namespace": "nullplatform",
            "labels": {
              "nullplatform": "true",
              "application_id": "app-123",
              "scope_id": "scope-456"
            },
            "creationTimestamp": "2024-01-01T10:00:00Z"
          },
          "spec": {
            "nodeName": "node-1",
            "containers": [{
              "name": "main",
              "resources": {
                "requests": {"cpu": "100m", "memory": "128Mi"},
                "limits": {"cpu": "500m", "memory": "512Mi"}
              }
            }]
          },
          "status": {
            "phase": "Running",
            "podIP": "10.0.0.5",
            "containerStatuses": [{
              "name": "main",
              "ready": true,
              "image": "myapp:latest"
            }]
          }
        },
        {
          "metadata": {
            "name": "app-pod-2",
            "namespace": "nullplatform",
            "labels": {
              "nullplatform": "true",
              "application_id": "app-123",
              "scope_id": "scope-456"
            },
            "creationTimestamp": "2024-01-01T11:00:00Z"
          },
          "spec": {
            "nodeName": "spot-node-1",
            "containers": [{
              "name": "main",
              "resources": {
                "requests": {"cpu": "200m", "memory": "256Mi"},
                "limits": {"cpu": "1000m", "memory": "1Gi"}
              }
            }]
          },
          "status": {
            "phase": "Running",
            "podIP": "10.0.0.6",
            "containerStatuses": [{
              "name": "main",
              "ready": true,
              "image": "myapp:arm64"
            }]
          }
        }
      ]
    }'
  }
  export -f kubectl
}

teardown() {
  unset NAMESPACE_OVERRIDE APPLICATION_ID SCOPE_ID DEPLOYMENT_ID LIMIT
  unset -f kubectl
}

# =============================================================================
# Full JSON structure validation
# =============================================================================
@test "instance/list: produces complete JSON with all expected fields" {
  run bash "$SCRIPT"

  assert_equal "$status" "0"

  local expected_json='{
    "results": [
      {
        "id": "app-pod-1",
        "selector": {
          "nullplatform": "true",
          "application_id": "app-123",
          "scope_id": "scope-456"
        },
        "details": {
          "namespace": "nullplatform",
          "ip": "10.0.0.5",
          "dns": "10.0.0.5.nullplatform.pod.cluster.local",
          "cpu": {
            "requested": 0.1,
            "limit": 0.5
          },
          "memory": {
            "requested": "128Mi",
            "limit": "512Mi"
          },
          "architecture": "x86"
        },
        "state": "Running",
        "launch_time": "2024-01-01T10:00:00Z",
        "spot": false
      },
      {
        "id": "app-pod-2",
        "selector": {
          "nullplatform": "true",
          "application_id": "app-123",
          "scope_id": "scope-456"
        },
        "details": {
          "namespace": "nullplatform",
          "ip": "10.0.0.6",
          "dns": "10.0.0.6.nullplatform.pod.cluster.local",
          "cpu": {
            "requested": 0.2,
            "limit": 1
          },
          "memory": {
            "requested": "256Mi",
            "limit": "1Gi"
          },
          "architecture": "arm64"
        },
        "state": "Running",
        "launch_time": "2024-01-01T11:00:00Z",
        "spot": true
      }
    ]
  }'

  assert_json_equal "$output" "$expected_json" "Complete instance list output"
}

# =============================================================================
# LIMIT handling
# =============================================================================
@test "instance/list: respects LIMIT parameter" {
  export LIMIT=1

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  local count=$(echo "$output" | jq '.results | length')
  assert_equal "$count" "1"

  local id=$(echo "$output" | jq -r '.results[0].id')
  assert_equal "$id" "app-pod-1"
}

# =============================================================================
# Label selector construction
# =============================================================================
@test "instance/list: builds label selector with all filters" {
  kubectl() {
    if [[ "$*" == *"-l nullplatform=true,application_id=app-123,scope_id=scope-456,deployment_id=deploy-789"* ]]; then
      echo '{"items":[]}'
    else
      echo "Unexpected label selector: $*" >&2
      return 1
    fi
  }
  export -f kubectl

  run bash "$SCRIPT"

  assert_equal "$status" "0"
}

@test "instance/list: builds label selector with only APPLICATION_ID" {
  export SCOPE_ID=""
  export DEPLOYMENT_ID=""

  kubectl() {
    if [[ "$*" == *"-l nullplatform=true,application_id=app-123"* ]]; then
      echo '{"items":[]}'
    else
      echo "Unexpected label selector: $*" >&2
      return 1
    fi
  }
  export -f kubectl

  run bash "$SCRIPT"

  assert_equal "$status" "0"
}

@test "instance/list: excludes null filter values from label selector" {
  export APPLICATION_ID="null"
  export SCOPE_ID="null"
  export DEPLOYMENT_ID="null"

  kubectl() {
    if [[ "$*" == *"-l nullplatform=true"* ]] && [[ "$*" != *"application_id"* ]]; then
      echo '{"items":[]}'
    else
      echo "Unexpected label selector: $*" >&2
      return 1
    fi
  }
  export -f kubectl

  run bash "$SCRIPT"

  assert_equal "$status" "0"
}

# =============================================================================
# Namespace handling
# =============================================================================
@test "instance/list: uses default nullplatform namespace" {
  kubectl() {
    if [[ "$*" == *"-n nullplatform"* ]]; then
      echo '{"items":[]}'
    else
      echo "Expected default namespace: $*" >&2
      return 1
    fi
  }
  export -f kubectl

  run bash "$SCRIPT"

  assert_equal "$status" "0"
}

@test "instance/list: uses NAMESPACE_OVERRIDE when set" {
  export NAMESPACE_OVERRIDE="custom-namespace"

  kubectl() {
    if [[ "$*" == *"-n custom-namespace"* ]]; then
      echo '{"items":[]}'
    else
      echo "Expected namespace override: $*" >&2
      return 1
    fi
  }
  export -f kubectl

  run bash "$SCRIPT"

  assert_equal "$status" "0"
}

# =============================================================================
# Edge cases
# =============================================================================
@test "instance/list: handles empty pod list" {
  kubectl() {
    echo '{"items":[]}'
  }
  export -f kubectl

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_json_equal "$output" '{"results": []}' "Empty pod list"
}

@test "instance/list: handles pending pod without IP" {
  kubectl() {
    echo '{
      "items": [{
        "metadata": {
          "name": "pending-pod",
          "namespace": "nullplatform",
          "labels": {"nullplatform": "true"},
          "creationTimestamp": "2024-01-01T10:00:00Z"
        },
        "spec": {
          "containers": [{
            "name": "main",
            "resources": {}
          }]
        },
        "status": {
          "phase": "Pending",
          "containerStatuses": [{
            "name": "main",
            "image": "myapp:latest"
          }]
        }
      }]
    }'
  }
  export -f kubectl

  run bash "$SCRIPT"

  assert_equal "$status" "0"

  local expected_json='{
    "results": [{
      "id": "pending-pod",
      "selector": {"nullplatform": "true"},
      "details": {
        "namespace": "nullplatform",
        "ip": "pending",
        "dns": "pending",
        "cpu": {"requested": 0, "limit": 0},
        "memory": {"requested": "0Mi", "limit": "0Mi"},
        "architecture": "x86"
      },
      "state": "Pending",
      "launch_time": "2024-01-01T10:00:00Z",
      "spot": false
    }]
  }'

  assert_json_equal "$output" "$expected_json" "Pending pod output"
}

@test "instance/list: handles pod without nodeName (spot defaults to false)" {
  kubectl() {
    echo '{
      "items": [{
        "metadata": {
          "name": "no-node-pod",
          "namespace": "nullplatform",
          "labels": {},
          "creationTimestamp": "2024-01-01T10:00:00Z"
        },
        "spec": {
          "containers": [{
            "name": "main",
            "resources": {
              "requests": {"cpu": "500m", "memory": "256Mi"},
              "limits": {"cpu": "1000m", "memory": "512Mi"}
            }
          }]
        },
        "status": {
          "phase": "Pending",
          "podIP": "10.0.0.7",
          "containerStatuses": [{
            "name": "main",
            "image": "myapp:latest"
          }]
        }
      }]
    }'
  }
  export -f kubectl

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  local spot=$(echo "$output" | jq -r '.results[0].spot')
  assert_equal "$spot" "false"
}
