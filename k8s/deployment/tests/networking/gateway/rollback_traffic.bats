#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/networking/gateway/rollback_traffic - traffic rollback
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export DEPLOYMENT_ID="deploy-new-123"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR"
  export SCOPE_ID="scope-123"
  export INGRESS_VISIBILITY="internet-facing"
  export TEMPLATE="$BATS_TEST_TMPDIR/template.yaml"

  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "current_active_deployment": "deploy-old-456"
    },
    "deployment": {
      "id": "deploy-new-123"
    }
  }'

  # Create a mock template
  echo 'kind: Ingress' > "$TEMPLATE"

  # Mock gomplate
  gomplate() {
    local out_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --out) out_file="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "# Generated" > "$out_file"
    return 0
  }
  export -f gomplate
}

teardown() {
  unset CONTEXT
  unset -f gomplate
}

# =============================================================================
# Success Case
# =============================================================================
@test "rollback_traffic: succeeds with all expected logging" {
  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/rollback_traffic"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Rolling back traffic to previous deployment..."
  assert_contains "$output" "📋 Current deployment: deploy-new-123"
  assert_contains "$output" "📋 Rollback target: deploy-old-456"
  assert_contains "$output" "📝 Creating ingress for rollback deployment..."
  assert_contains "$output" "🔍 Creating internet-facing ingress..."
  assert_contains "$output" "✅ Traffic rollback configuration created"
}

@test "rollback_traffic: creates ingress for old deployment" {
  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/rollback_traffic"

  [ "$status" -eq 0 ]
  [ -f "$OUTPUT_DIR/ingress-$SCOPE_ID-deploy-old-456.yaml" ]
}

# =============================================================================
# Error Cases
# =============================================================================
@test "rollback_traffic: fails with full troubleshooting when route_traffic fails" {
  gomplate() {
    return 1
  }
  export -f gomplate

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/rollback_traffic"

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Rolling back traffic to previous deployment..."
  assert_contains "$output" "📝 Creating ingress for rollback deployment..."
  assert_contains "$output" "❌ Failed to build ingress template"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# Integration Tests
# =============================================================================
@test "rollback_traffic: calls route_traffic with blue deployment id in context" {
  local mock_dir="$BATS_TEST_TMPDIR/mock_service"
  mkdir -p "$mock_dir/deployment/networking/gateway"

  cat > "$mock_dir/deployment/networking/gateway/route_traffic" << 'MOCK_SCRIPT'
#!/bin/bash
echo "CAPTURED_DEPLOYMENT_ID=$DEPLOYMENT_ID" >> "$BATS_TEST_TMPDIR/captured_values"
echo "CAPTURED_CONTEXT_DEPLOYMENT_ID=$(echo "$CONTEXT" | jq -r .deployment.id)" >> "$BATS_TEST_TMPDIR/captured_values"
MOCK_SCRIPT
  chmod +x "$mock_dir/deployment/networking/gateway/route_traffic"

  run bash -c "
    export SERVICE_PATH='$mock_dir'
    export DEPLOYMENT_ID='$DEPLOYMENT_ID'
    export CONTEXT='$CONTEXT'
    export BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR'
    source '$PROJECT_ROOT/k8s/deployment/networking/gateway/rollback_traffic'
  "

  [ "$status" -eq 0 ]

  # Verify route_traffic was called with blue deployment id
  source "$BATS_TEST_TMPDIR/captured_values"
  assert_equal "$CAPTURED_DEPLOYMENT_ID" "deploy-old-456"
  assert_equal "$CAPTURED_CONTEXT_DEPLOYMENT_ID" "deploy-old-456"
}
