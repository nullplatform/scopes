#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/networking/gateway/ingress/route_traffic
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export OUTPUT_DIR="$BATS_TEST_TMPDIR"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-456"
  export INGRESS_VISIBILITY="internet-facing"

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
  MOCK_TEMPLATE="$BATS_TEST_TMPDIR/ingress-template.yaml"
  echo 'apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .scope.slug }}-ingress' > "$MOCK_TEMPLATE"
  export MOCK_TEMPLATE

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
    echo "# Generated ingress from $template_file" > "$out_file"
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
@test "ingress/route_traffic: succeeds with all expected logging" {
  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/ingress/route_traffic" --template="$MOCK_TEMPLATE"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<EOF
🔍 Creating internet-facing ingress...
📋 Scope: scope-123 | Deployment: deploy-456
📋 Template: $MOCK_TEMPLATE
📋 Output: $OUTPUT_DIR/ingress-scope-123-deploy-456.yaml
📝 Building ingress template...
✅ Ingress template created: $OUTPUT_DIR/ingress-scope-123-deploy-456.yaml
EOF
)
  assert_equal "$output" "$expected"
}

@test "ingress/route_traffic: displays correct visibility type for internal" {
  export INGRESS_VISIBILITY="internal"

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/ingress/route_traffic" --template="$MOCK_TEMPLATE"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Creating internal ingress..."
}

@test "ingress/route_traffic: generates ingress file and cleans up context" {
  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/ingress/route_traffic" --template="$MOCK_TEMPLATE"

  [ "$status" -eq 0 ]
  [ -f "$OUTPUT_DIR/ingress-$SCOPE_ID-$DEPLOYMENT_ID.yaml" ]
  # Uses context-$SCOPE_ID.json (no deployment ID) unlike parent
  [ ! -f "$OUTPUT_DIR/context-$SCOPE_ID.json" ]
}

# =============================================================================
# Error Cases
# =============================================================================
@test "ingress/route_traffic: fails with full troubleshooting when template missing" {
  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/ingress/route_traffic"

  [ "$status" -eq 1 ]
  local expected
  expected=$(cat <<'EOF'
❌ Template argument is required
💡 Possible causes:
   - Missing --template= argument
🔧 How to fix:
   - Provide template: --template=/path/to/template.yaml
EOF
)
  assert_equal "$output" "$expected"
}

@test "ingress/route_traffic: fails with full troubleshooting when gomplate fails" {
  gomplate() {
    echo "template: template.yaml:5: function 'undefined' not defined" >&2
    return 1
  }
  export -f gomplate

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/ingress/route_traffic" --template="$MOCK_TEMPLATE"

  [ "$status" -eq 1 ]
  local expected
  expected=$(cat <<EOF
🔍 Creating internet-facing ingress...
📋 Scope: scope-123 | Deployment: deploy-456
📋 Template: $MOCK_TEMPLATE
📋 Output: $OUTPUT_DIR/ingress-scope-123-deploy-456.yaml
📝 Building ingress template...
template: template.yaml:5: function 'undefined' not defined
❌ Failed to build ingress template
💡 Possible causes:
   - Template file does not exist or is invalid
   - Scope attributes may be missing
🔧 How to fix:
   - Verify template exists: ls -la $MOCK_TEMPLATE
   - Verify that your scope has all required attributes
EOF
)
  assert_equal "$output" "$expected"
}

@test "ingress/route_traffic: cleans up context file on gomplate failure" {
  gomplate() {
    return 1
  }
  export -f gomplate

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/ingress/route_traffic" --template="$MOCK_TEMPLATE"

  [ "$status" -eq 1 ]
  [ ! -f "$OUTPUT_DIR/context-$SCOPE_ID.json" ]
}

# =============================================================================
# Integration Tests
# =============================================================================
@test "ingress/route_traffic: parses template argument correctly" {
  CAPTURED_TEMPLATE=""
  gomplate() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --file) CAPTURED_TEMPLATE="$2"; shift 2 ;;
        --out) echo "# Generated" > "$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    return 0
  }
  export -f gomplate
  export CAPTURED_TEMPLATE

  run bash "$PROJECT_ROOT/k8s/deployment/networking/gateway/ingress/route_traffic" --template="$MOCK_TEMPLATE"

  [ "$status" -eq 0 ]
}
