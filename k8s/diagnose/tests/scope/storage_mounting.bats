#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/storage_mounting
# =============================================================================

strip_ansi() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export LABEL_SELECTOR="app=test"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  export PODS_FILE="$(mktemp)"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$PODS_FILE"
  unset -f kubectl 2>/dev/null || true
}

# =============================================================================
# Success Tests
# =============================================================================
@test "scope/storage_mounting: success when PVC is Bound" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "my-pvc"}}],
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  run bash -c "
    kubectl() {
      case \"\$*\" in
        *'get pvc'*'-o jsonpath'*) echo 'Bound' ;;
      esac
    }
    export -f kubectl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: PVC my-pvc is Bound"
  assert_contains "$stripped" "All volumes mounted successfully for"
  assert_contains "$stripped" "pod(s)"
}

@test "scope/storage_mounting: success when no PVCs (no volumes)" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "All volumes mounted successfully for"
}

@test "scope/storage_mounting: success with multiple PVCs all Bound" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "volumes": [
        {"name": "data", "persistentVolumeClaim": {"claimName": "pvc-data"}},
        {"name": "logs", "persistentVolumeClaim": {"claimName": "pvc-logs"}}
      ],
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  run bash -c "
    kubectl() {
      case \"\$*\" in
        *'get pvc'*'-o jsonpath'*) echo 'Bound' ;;
      esac
    }
    export -f kubectl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: PVC pvc-data is Bound"
  assert_contains "$stripped" "Pod pod-1: PVC pvc-logs is Bound"
  assert_contains "$stripped" "All volumes mounted successfully for"
}

# =============================================================================
# Failure Tests
# =============================================================================
@test "scope/storage_mounting: failed when PVC is Pending" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "my-pvc"}}],
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  run bash -c "
    kubectl() {
      case \"\$*\" in
        *'get pvc'*'-o jsonpath'*) echo 'Pending' ;;
        *'get pvc'*'-o json'*) echo '{\"spec\":{\"storageClassName\":\"gp2\",\"resources\":{\"requests\":{\"storage\":\"10Gi\"}}}}' ;;
      esac
    }
    export -f kubectl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: PVC my-pvc is in Pending state"
  assert_contains "$stripped" "Storage Class: gp2"
  assert_contains "$stripped" "Requested Size: 10Gi"
  assert_contains "$stripped" "Check if StorageClass exists and has available capacity"
}

@test "scope/storage_mounting: updates status to failed on Pending PVC" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "my-pvc"}}],
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  kubectl() {
    case "$*" in
      *"get pvc"*"-o jsonpath"*) echo "Pending" ;;
      *"get pvc"*"-o json"*) echo '{"spec":{"storageClassName":"gp2","resources":{"requests":{"storage":"10Gi"}}}}' ;;
    esac
  }
  export -f kubectl

  source "$BATS_TEST_DIRNAME/../../scope/storage_mounting"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"

  unset -f kubectl
}

# =============================================================================
# Warning Tests
# =============================================================================
@test "scope/storage_mounting: warns ContainerCreating with PVCs" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "containerStatuses": [{
        "name": "app",
        "ready": false,
        "state": {"waiting": {"reason": "ContainerCreating"}}
      }]
    },
    "spec": {
      "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "my-pvc"}}],
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  run bash -c "
    kubectl() {
      case \"\$*\" in
        *'get pvc'*'-o jsonpath'*) echo 'Bound' ;;
      esac
    }
    export -f kubectl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: Containers waiting in ContainerCreating (may be waiting for volumes)"
}

@test "scope/storage_mounting: warns on unknown PVC status" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "my-pvc"}}],
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  run bash -c "
    kubectl() {
      case \"\$*\" in
        *'get pvc'*'-o jsonpath'*) echo 'Lost' ;;
      esac
    }
    export -f kubectl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: PVC my-pvc status is Lost"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "scope/storage_mounting: skips when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "scope/storage_mounting: volumes without PVC are ignored" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "volumes": [
        {"name": "config", "configMap": {"name": "my-config"}},
        {"name": "secret", "secret": {"secretName": "my-secret"}}
      ],
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'"

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "All volumes mounted successfully for"
}

@test "scope/storage_mounting: updates status to success when all PVCs bound" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
      }]
    },
    "spec": {
      "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "my-pvc"}}],
      "containers": [{"name": "app"}]
    }
  }]
}
EOF

  kubectl() {
    case "$*" in
      *"get pvc"*"-o jsonpath"*) echo "Bound" ;;
    esac
  }
  export -f kubectl

  source "$BATS_TEST_DIRNAME/../../scope/storage_mounting"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"

  unset -f kubectl
}

@test "scope/storage_mounting: multiple pods with mixed PVC states" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [
    {
      "metadata": {"name": "pod-1"},
      "status": {
        "phase": "Running",
        "containerStatuses": [{
          "name": "app",
          "ready": true,
          "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
        }]
      },
      "spec": {
        "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "pvc-bound"}}],
        "containers": [{"name": "app"}]
      }
    },
    {
      "metadata": {"name": "pod-2"},
      "status": {
        "phase": "Pending",
        "containerStatuses": [{
          "name": "app",
          "ready": false,
          "state": {"waiting": {"reason": "ContainerCreating"}}
        }]
      },
      "spec": {
        "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "pvc-pending"}}],
        "containers": [{"name": "app"}]
      }
    }
  ]
}
EOF

  run bash -c "
    kubectl() {
      case \"\$*\" in
        *'get pvc'*'pvc-bound'*'-o jsonpath'*) echo 'Bound' ;;
        *'get pvc'*'pvc-pending'*'-o jsonpath'*) echo 'Pending' ;;
        *'get pvc'*'pvc-pending'*'-o json'*) echo '{\"spec\":{\"storageClassName\":\"gp3\",\"resources\":{\"requests\":{\"storage\":\"20Gi\"}}}}' ;;
      esac
    }
    export -f kubectl
    source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/storage_mounting'
  "

  [ "$status" -eq 0 ]
  stripped=$(strip_ansi "$output")
  assert_contains "$stripped" "Pod pod-1: PVC pvc-bound is Bound"
  assert_contains "$stripped" "Pod pod-2: PVC pvc-pending is in Pending state"
  assert_contains "$stripped" "Storage Class: gp3"
  assert_contains "$stripped" "Requested Size: 20Gi"
  assert_contains "$stripped" "Pod pod-2: Containers waiting in ContainerCreating (may be waiting for volumes)"
}
