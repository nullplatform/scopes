#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/gateway/build_gateway
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/gateway/build_gateway"

  # Create temp output directory
  export OUTPUT_DIR="$(mktemp -d)"
  export SCOPE_ID="scope-123"
  export SCOPE_DOMAIN="test.nullapps.io"
  export INGRESS_VISIBILITY="internet-facing"
  export CONTEXT='{"scope":{"id":"scope-123","domain":"test.nullapps.io"}}'

  # Create a mock template
  export TEMPLATE="$(mktemp)"
  echo '{{ .scope.domain }}' > "$TEMPLATE"

  # Mock gomplate
  gomplate() {
    local out_file=""
    local in_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --out) out_file="$2"; shift 2 ;;
        --file) in_file="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [ -n "$out_file" ]; then
      echo "rendered-ingress-content" > "$out_file"
    fi
    return 0
  }
  export -f gomplate
}

teardown() {
  rm -rf "$OUTPUT_DIR"
  rm -f "$TEMPLATE"
  unset -f gomplate
}

# =============================================================================
# Success flow
# =============================================================================
@test "build_gateway: success flow - displays all messages and renders template" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Building gateway ingress..."
  assert_contains "$output" "📋 Scope: scope-123 | Domain: test.nullapps.io | Visibility: internet-facing"
  assert_contains "$output" "📝 Building template: $TEMPLATE"
  assert_contains "$output" "✅ Ingress manifest created: $OUTPUT_DIR/ingress-scope-123-internet-facing.yaml"
}

@test "build_gateway: generates correct ingress file path" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_file_exists "$OUTPUT_DIR/ingress-scope-123-internet-facing.yaml"
}

@test "build_gateway: cleans up context JSON file after rendering" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_file_not_exists "$OUTPUT_DIR/context-scope-123.json"
}

@test "build_gateway: writes CONTEXT to temporary context file path" {
  gomplate() {
    local context_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -c) context_file="${2#*.=}"; shift 2 ;;
        --out)
          echo "rendered" > "$2"; shift 2
          ;;
        *) shift ;;
      esac
    done
    if [ -n "$context_file" ] && [ -f "$context_file" ]; then
      local content
      content=$(cat "$context_file")
      if [[ "$content" == *"scope-123"* ]]; then
        return 0
      fi
    fi
    return 1
  }
  export -f gomplate

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
}

@test "build_gateway: uses internal visibility in file name" {
  export INGRESS_VISIBILITY="internal"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Scope: scope-123 | Domain: test.nullapps.io | Visibility: internal"
  assert_contains "$output" "✅ Ingress manifest created: $OUTPUT_DIR/ingress-scope-123-internal.yaml"
  assert_file_exists "$OUTPUT_DIR/ingress-scope-123-internal.yaml"
}

# =============================================================================
# gomplate failure
# =============================================================================
@test "build_gateway: fails with error details when gomplate fails" {
  gomplate() {
    return 1
  }
  export -f gomplate

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to render ingress template"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The template file may contain invalid gomplate syntax"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Check the template is valid gomplate YAML"
}
