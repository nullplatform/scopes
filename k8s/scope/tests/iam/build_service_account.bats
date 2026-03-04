#!/usr/bin/env bats
# =============================================================================
# Unit tests for iam/build_service_account - Service account setup from IAM role
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

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
