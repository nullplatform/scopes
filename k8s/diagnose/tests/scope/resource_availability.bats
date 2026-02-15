#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/scope/resource_availability
# =============================================================================

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
}

# =============================================================================
# Success Tests
# =============================================================================
@test "scope/resource_availability: success when all pods scheduled" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "conditions": [{"type": "PodScheduled", "status": "True"}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/resource_availability'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "successfully scheduled"
}

@test "scope/resource_availability: updates check result to success" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {"phase": "Running"}
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/resource_availability"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# Failure Tests - Unschedulable
# =============================================================================
@test "scope/resource_availability: fails on unschedulable pods" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "conditions": [{
        "type": "PodScheduled",
        "status": "False",
        "reason": "Unschedulable",
        "message": "0/3 nodes are available: 3 Insufficient cpu"
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/resource_availability'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Cannot be scheduled"
  assert_contains "$output" "Insufficient cpu"
}

@test "scope/resource_availability: detects insufficient CPU" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "conditions": [{
        "reason": "Unschedulable",
        "message": "Insufficient cpu"
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/resource_availability'"

  assert_contains "$output" "Insufficient CPU"
}

@test "scope/resource_availability: detects insufficient memory" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "conditions": [{
        "reason": "Unschedulable",
        "message": "Insufficient memory"
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/resource_availability'"

  assert_contains "$output" "Insufficient memory"
}

@test "scope/resource_availability: shows action for resource issues" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "conditions": [{
        "reason": "Unschedulable",
        "message": "No nodes available"
      }]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/resource_availability'"

  assert_contains "$output" "🔧"
  assert_contains "$output" "Reduce resource requests"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "scope/resource_availability: skips when no pods" {
  echo '{"items":[]}' > "$PODS_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/resource_availability'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}

# =============================================================================
# Status Update Tests
# =============================================================================
@test "scope/resource_availability: updates status to failed on unschedulable" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Pending",
      "conditions": [{
        "reason": "Unschedulable",
        "message": "No resources"
      }]
    }
  }]
}
EOF

  source "$BATS_TEST_DIRNAME/../../scope/resource_availability"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "failed"
}

# =============================================================================
# Edge Cases
# =============================================================================
@test "scope/resource_availability: ignores running pods even if previously pending" {
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "pod-1"},
    "status": {
      "phase": "Running",
      "conditions": [{"type": "PodScheduled", "status": "True"}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../scope/resource_availability'"

  [ "$status" -eq 0 ]
  # Should not contain "Cannot be scheduled"
  [[ ! "$output" =~ "Cannot be scheduled" ]]
}
