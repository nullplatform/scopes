#!/usr/bin/env bats
# =============================================================================
# Unit tests for iam/build_service_account - Service account setup from IAM role
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  # Script under test
  export SCRIPT="$BATS_TEST_DIRNAME/../../iam/build_service_account"

  # Default environment variables
  export SCOPE_ID="test-scope-123"
  export OUTPUT_DIR="$(mktemp -d)"
  export SERVICE_ACCOUNT_TEMPLATE="/templates/service_account.yaml"
  export CONTEXT='{"namespace":"test-ns","scope":{"id":"123"}}'

  # Mock aws - default success
  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws

  # Mock gomplate - default success
  gomplate() {
    return 0
  }
  export -f gomplate

  # Mock rm
  rm() {
    return 0
  }
  export -f rm
}

teardown() {
  rm -rf "$OUTPUT_DIR" 2>/dev/null || true
  unset -f aws gomplate rm 2>/dev/null || true
}

# =============================================================================
# Test: IAM disabled (ENABLED=false) skips service account setup
# =============================================================================
@test "build_service_account: IAM disabled (ENABLED=false) skips with message" {
  export IAM='{"ENABLED":"false"}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping service account setup"
}

# =============================================================================
# Test: IAM disabled (ENABLED=null) skips service account setup
# =============================================================================
@test "build_service_account: IAM disabled (ENABLED=null) skips with message" {
  export IAM='{"ENABLED":null}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping service account setup"
}

# =============================================================================
# Test: IAM not set defaults to empty JSON and skips
# =============================================================================
@test "build_service_account: IAM not set defaults to empty JSON and skips" {
  unset IAM

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping service account setup"
}

# =============================================================================
# Test: Success flow - finds role, builds template
# =============================================================================
@test "build_service_account: success flow verifies all log messages in order" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Looking for IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "📝 Building service account template: /templates/service_account.yaml"
  assert_contains "$output" "✅ Service account template built successfully"
}

# =============================================================================
# Test: Error - aws iam get-role fails (non-delete action)
# =============================================================================
@test "build_service_account: aws iam get-role failure shows error with hints" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "An error occurred (AccessDenied) when calling the GetRole operation" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "🔍 Looking for IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "❌ Failed to find IAM role 'test-prefix-test-scope-123'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The IAM role may not exist or the agent lacks IAM permissions"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify the role exists: aws iam get-role --role-name test-prefix-test-scope-123"
  assert_contains "$output" "• Check IAM permissions for the agent role"
}

# =============================================================================
# Test: Delete action with NoSuchEntity skips service account deletion
# =============================================================================
@test "build_service_account: delete action with NoSuchEntity skips deletion" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  export ACTION="delete"

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "An error occurred (NoSuchEntity) when calling the GetRole operation: Role with name test-prefix-test-scope-123 cannot be found." >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM role 'test-prefix-test-scope-123' does not exist, skipping service account deletion"
}

# =============================================================================
# Test: Non-delete action with NoSuchEntity fails
# =============================================================================
@test "build_service_account: non-delete action with NoSuchEntity fails with error" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  unset ACTION

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "An error occurred (NoSuchEntity) when calling the GetRole operation: Role with name test-prefix-test-scope-123 cannot be found." >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to find IAM role 'test-prefix-test-scope-123'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The IAM role may not exist or the agent lacks IAM permissions"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# Test: Error - gomplate template generation fails
# =============================================================================
@test "build_service_account: gomplate failure shows template error with hints" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  gomplate() {
    echo "Error: template rendering failed" >&2
    return 1
  }
  export -f gomplate

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "📝 Building service account template: /templates/service_account.yaml"
  assert_contains "$output" "❌ Failed to build service account template"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The template file may be missing or contain invalid gomplate syntax"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify template exists: ls -la /templates/service_account.yaml"
  assert_contains "$output" "• Check the template is a valid Kubernetes ServiceAccount YAML with correct gomplate expressions"
}

render_real_template() {
  unset -f gomplate
  export SERVICE_ACCOUNT_TEMPLATE="$PROJECT_ROOT/k8s/scope/templates/service-account.yaml.tpl"
  export CONTEXT='{
    "k8s_namespace": "test-ns",
    "k8s_modifiers": {},
    "application": {"id": 42, "slug": "test-app"},
    "scope": {"id": 123, "slug": "test-scope"},
    "account": {"id": 20, "slug": "test-account"},
    "namespace": {"id": 300, "slug": "test-namespace"}
  }'
}

@test "build_service_account: a pattern prefix names the service account from the context" {
  export IAM='{"ENABLED":"true","PREFIX":"{.account.slug}-{.namespace.slug}"}'
  export CONTEXT='{"k8s_namespace":"test-ns","account":{"slug":"acme"},"namespace":{"slug":"payments"},"scope":{"id":"123"}}'
  kubectl() { return 0; }
  export -f kubectl

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Looking for IAM role: acme-payments-test-scope-123"
}

@test "build_service_account: a pattern prefix keeps the name of the scope's existing service account" {
  export IAM='{"ENABLED":"true","PREFIX":"{.account.slug}-{.namespace.slug}"}'
  export CONTEXT='{"k8s_namespace":"test-ns","account":{"slug":"acme"},"namespace":{"slug":"renamed"},"scope":{"id":"123"}}'
  kubectl() {
    case "$*" in
      "get serviceaccounts -n test-ns -l scope_id=test-scope-123"*) printf '%s' "acme-payments-test-scope-123" ;;
    esac
  }
  export -f kubectl
  aws() {
    case "$*" in
      *"iam get-role"*"scope_id"*) echo "test-scope-123" ;;
      *"iam get-role"*) echo "arn:aws:iam::123456789012:role/acme-payments-test-scope-123" ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Looking for IAM role: acme-payments-test-scope-123"
}

@test "build_service_account: irsa annotates the service account with the role ARN" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  render_real_template

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  rendered="$OUTPUT_DIR/service_account-$SCOPE_ID.yaml"
  assert_equal "$(yq -r '.metadata.annotations["eks.amazonaws.com/role-arn"]' "$rendered")" "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
  assert_equal "$(yq -r '.metadata.name' "$rendered")" "test-prefix-test-scope-123"
}

@test "build_service_account: pod_identity leaves the service account without the IRSA annotation" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix","MODE":"pod_identity"}'
  render_real_template

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  rendered="$OUTPUT_DIR/service_account-$SCOPE_ID.yaml"
  assert_equal "$(yq -r '.metadata.annotations' "$rendered")" "null"
  assert_equal "$(yq -r '.metadata.name' "$rendered")" "test-prefix-test-scope-123"
  assert_equal "$(yq -r '.metadata.labels.scope_id' "$rendered")" "123"
}

@test "build_service_account: a prefix that cannot be rendered fails before looking up the role" {
  export IAM='{"ENABLED":"true","PREFIX":"{.account.slug | ascii}"}'
  export CONTEXT='{"k8s_namespace":"test-ns","scope":{"id":"123"}}'
  export AWS_LOG="$OUTPUT_DIR/aws.log"
  kubectl() { return 0; }
  aws() { echo "$*" >> "$AWS_LOG"; }
  export -f kubectl aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Could not render the IAM role name from prefix '{.account.slug | ascii}'"
  assert_empty "$(cat "$AWS_LOG" 2>/dev/null)"
}

@test "build_service_account: gke builds the application and environment service account without an IAM role or scope labels" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix","MODE":"gke"}'
  export AWS_LOG="$OUTPUT_DIR/aws.log"
  aws() { echo "$*" >> "$AWS_LOG"; return 1; }
  export -f aws
  render_real_template
  CONTEXT=$(echo "$CONTEXT" | jq '.scope.dimensions = {"environment": "Production"}')

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM mode is gke, building service account 'np-42-production' without an IAM role"
  assert_empty "$(cat "$AWS_LOG" 2>/dev/null)"
  rendered="$OUTPUT_DIR/service_account-$SCOPE_ID.yaml"
  assert_equal "$(yq -r '.metadata.name' "$rendered")" "np-42-production"
  assert_equal "$(yq -r '.metadata.namespace' "$rendered")" "test-ns"
  assert_equal "$(yq -r '.metadata.annotations' "$rendered")" "null"
  assert_equal "$(yq -r '.metadata.labels.application_id' "$rendered")" "42"
  assert_equal "$(yq -r '.metadata.labels.scope_id' "$rendered")" "null"
  assert_equal "$(yq -r '.metadata.labels.scope' "$rendered")" "null"
}

@test "build_service_account: gke renders the same service account for every scope of the application in the environment" {
  export IAM='{"ENABLED":"true","MODE":"gke"}'
  render_real_template
  CONTEXT=$(echo "$CONTEXT" | jq '.scope.dimensions = {"environment": "production"}')
  first="$OUTPUT_DIR/first.yaml"

  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "0"
  cp "$OUTPUT_DIR/service_account-$SCOPE_ID.yaml" "$first"

  export SCOPE_ID="other-scope-456"
  CONTEXT=$(echo "$CONTEXT" | jq '.scope.id = 456 | .scope.slug = "other-scope"')
  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "0"

  assert_equal "$(cat "$OUTPUT_DIR/service_account-other-scope-456.yaml")" "$(cat "$first")"
}

@test "build_service_account: gke fails when the scope has no environment dimension" {
  export IAM='{"ENABLED":"true","MODE":"gke"}'
  render_real_template

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Could not name the service account of scope test-scope-123: IAM.MODE gke needs the scope's 'environment' dimension"
  assert_equal "$(ls "$OUTPUT_DIR")" ""
}

@test "build_service_account: gke on delete keeps the shared service account without calling AWS" {
  export IAM='{"ENABLED":"true","MODE":"gke"}'
  export ACTION="delete"
  export AWS_LOG="$OUTPUT_DIR/aws.log"
  aws() { echo "$*" >> "$AWS_LOG"; return 1; }
  kubectl() { echo "kubectl $*" >> "$AWS_LOG"; }
  export -f aws kubectl
  render_real_template
  CONTEXT=$(echo "$CONTEXT" | jq '.scope.dimensions = {"environment": "production"}')

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM mode is gke, keeping the service account: other scopes of the application in this environment may use it"
  assert_empty "$(cat "$AWS_LOG" 2>/dev/null)"
  assert_equal "$(ls "$OUTPUT_DIR")" ""
}
