#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/image_pull_status - image pull verification
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  # Setup required environment
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
}

# =============================================================================
# Success Tests
# =============================================================================
@test "scope/image_pull_status: success when all images pulled" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "ready": true,
        "state": {"running": {}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/image_pull_status'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "images pulled successfully"
}

@test "scope/image_pull_status: updates check result to success" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "containerStatuses": [{
        "name": "app",
        "state": {"running": {}}
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/image_pull_status"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests - ImagePullBackOff
# =============================================================================
@test "scope/image_pull_status: fails on ImagePullBackOff" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{"name": "app", "image": "myregistry/myimage:v1"}]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "state": {
          "waiting": {
            "reason": "ImagePullBackOff",
            "message": "rpc error: code = Unknown desc = unauthorized"
          }
        }
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/image_pull_status'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "ImagePullBackOff"
  assert_contains "$output" "pod-1"
}

@test "scope/image_pull_status: shows image and error message" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{"name": "app", "image": "myregistry/myimage:v1"}]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "state": {
          "waiting": {
            "reason": "ImagePullBackOff",
            "message": "unauthorized access"
          }
        }
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/image_pull_status'"

  assert_contains "$output" "Image: myregistry/myimage:v1"
  assert_contains "$output" "Reason: unauthorized access"
}

@test "scope/image_pull_status: shows action for image pull errors" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{"name": "app", "image": "private/image:v1"}]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "state": {"waiting": {"reason": "ErrImagePull", "message": "pull access denied"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/image_pull_status'"

  assert_contains "$output" "🔧"
  assert_contains "$output" "imagePullSecrets"
}

# =============================================================================
# Failure Tests - ErrImagePull
# =============================================================================
@test "scope/image_pull_status: fails on ErrImagePull" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{"name": "app", "image": "nonexistent/image:v1"}]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "state": {"waiting": {"reason": "ErrImagePull", "message": "image not found"}}
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/image_pull_status'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "ErrImagePull"
}

@test "scope/image_pull_status: updates check result to failed on error" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [{"name": "app", "image": "bad/image:v1"}]
    },
    "status": {
      "containerStatuses": [{
        "name": "app",
        "state": {"waiting": {"reason": "ImagePullBackOff", "message": "error"}}
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/image_pull_status"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "scope/image_pull_status: skips when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/image_pull_status'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

# =============================================================================
# Multiple Containers Tests
# =============================================================================
@test "scope/image_pull_status: detects multiple container failures" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "spec": {
      "containers": [
        {"name": "app", "image": "app:v1"},
        {"name": "sidecar", "image": "sidecar:v1"}
      ]
    },
    "status": {
      "containerStatuses": [
        {"name": "app", "state": {"waiting": {"reason": "ImagePullBackOff", "message": "error1"}}},
        {"name": "sidecar", "state": {"waiting": {"reason": "ErrImagePull", "message": "error2"}}}
      ]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/image_pull_status'"

  assert_contains "$output" "app"
  assert_contains "$output" "sidecar"
}
