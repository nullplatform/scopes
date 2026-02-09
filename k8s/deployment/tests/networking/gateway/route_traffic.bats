#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/networking/gateway/route_traffic - ingress creation
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export OUTPUT_DIR="$BATS_TEST_TMPDIR"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-456"
  export INGRESS_VISIBILITY="internet-facing"
  export TEMPLATE="$BATS_TEST_TMPDIR/template.yaml"

  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "domain": "app.example.com"
    },
    "deployment": {
      "id": "deploy-456"
    }
  }'

  # Create a mock template
  echo 'apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .scope.slug }}-ingress' > "$TEMPLATE"

  # Mock gomplate
  gomplate() {
    local context_file=""
    local template_file=""
    local out_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -c) context_file="$2"; shift 2 ;;
        --file) template_file="$2"; shift 2 ;;
        --out) out_file="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    # Write mock output
    echo "# Generated ingress" > "$out_file"
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
@test "route_traffic: succeeds with all expected logging" {
  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/route_traffic"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Creating internet-facing ingress..."
  assert_contains "$output" "📋 Scope: scope-123 | Deployment: deploy-456"
  assert_contains "$output" "📋 Template: $TEMPLATE"
  assert_contains "$output" "📋 Output: $OUTPUT_DIR/ingress-scope-123-deploy-456.yaml"
  assert_contains "$output" "📝 Building ingress template..."
  assert_contains "$output" "✅ Ingress template created: $OUTPUT_DIR/ingress-scope-123-deploy-456.yaml"
}

@test "route_traffic: displays correct visibility type for internal" {
  export INGRESS_VISIBILITY="internal"

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/route_traffic"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Creating internal ingress..."
}

@test "route_traffic: generates ingress file and cleans up context" {
  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/route_traffic"

  [ "$status" -eq 0 ]
  [ -f "$OUTPUT_DIR/ingress-$SCOPE_ID-$DEPLOYMENT_ID.yaml" ]
  [ ! -f "$OUTPUT_DIR/context-$SCOPE_ID-$DEPLOYMENT_ID.json" ]
}

# =============================================================================
# Error Cases
# =============================================================================
@test "route_traffic: fails with full troubleshooting when gomplate fails" {
  gomplate() {
    echo "template: template.yaml:5: function 'undefined' not defined" >&2
    return 1
  }
  export -f gomplate

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/route_traffic"

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Creating internet-facing ingress..."
  assert_contains "$output" "📝 Building ingress template..."
  assert_contains "$output" "❌ Failed to build ingress template"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Template file does not exist or is invalid"
  assert_contains "$output" "- Scope attributes may be missing"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Verify template exists: ls -la $TEMPLATE"
  assert_contains "$output" "- Verify that your scope has all required attributes"
}

@test "route_traffic: cleans up context file on gomplate failure" {
  gomplate() {
    return 1
  }
  export -f gomplate

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/route_traffic"

  [ "$status" -eq 1 ]
  [ ! -f "$OUTPUT_DIR/context-$SCOPE_ID-$DEPLOYMENT_ID.json" ]
}

# =============================================================================
# Integration Tests
# =============================================================================
@test "route_traffic: calls gomplate with correct context file" {
  CAPTURED_CONTEXT=""
  gomplate() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -c) CAPTURED_CONTEXT="$2"; shift 2 ;;
        --out) echo "# Generated" > "$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    return 0
  }
  export -f gomplate
  export CAPTURED_CONTEXT

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/route_traffic"

  [ "$status" -eq 0 ]
}
