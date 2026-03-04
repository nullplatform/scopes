#!/usr/bin/env bats
# =============================================================================
# Unit tests for iam/delete_role - IAM role deletion with policy cleanup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Script under test
  export SCRIPT="$BATS_TEST_DIRNAME/../../iam/delete_role"

  # Default environment variables
  export SCOPE_ID="test-scope-123"
  export SERVICE_ACCOUNT_NAME="test-prefix-test-scope-123"

  # Mock aws - default success
  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
        ;;
      *"iam list-attached-role-policies"*)
        echo "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
        ;;
      *"iam detach-role-policy"*)
        return 0
        ;;
      *"iam list-role-policies"*)
        echo "inline-policy-1"
        ;;
      *"iam delete-role-policy"*)
        return 0
        ;;
      *"iam delete-role"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws
}

teardown() {
  unset -f aws 2>/dev/null || true
}

# =============================================================================
# Test: IAM disabled (ENABLED=false) skips role deletion
# =============================================================================
@test "delete_role: IAM disabled (ENABLED=false) skips with message" {
  export IAM='{"ENABLED":"false"}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping role deletion"
}

# =============================================================================
# Test: IAM disabled (ENABLED=null) skips role deletion
# =============================================================================
@test "delete_role: IAM disabled (ENABLED=null) skips with message" {
  export IAM='{"ENABLED":null}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping role deletion"
}

# =============================================================================
# Test: IAM not set defaults to empty JSON and skips
# =============================================================================
@test "delete_role: IAM not set defaults to empty JSON and skips" {
  unset IAM

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping role deletion"
}

# =============================================================================
# Test: Role not found (NoSuchEntity) skips deletion
# =============================================================================
@test "delete_role: role not found with NoSuchEntity skips deletion" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "An error occurred (NoSuchEntity) when calling the GetRole operation: The role with name test-prefix-test-scope-123 cannot be found." >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Looking for IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "📋 IAM role 'test-prefix-test-scope-123' does not exist, skipping role deletion"
}

# =============================================================================
# Test: Error - get-role fails (not NoSuchEntity)
# =============================================================================
@test "delete_role: get-role failure (not NoSuchEntity) shows error with hints" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "An error occurred (AccessDenied) when calling the GetRole operation: Access denied" >&2
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
# Test: Success flow - detach policies, delete inline, delete role
# =============================================================================
@test "delete_role: success flow detaches managed policies, deletes inline, deletes role" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Looking for IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "📝 Detaching managed policies..."
  assert_contains "$output" "📋 Detaching policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  assert_contains "$output" "✅ Detached policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  assert_contains "$output" "📝 Deleting inline policies..."
  assert_contains "$output" "📋 Deleting inline policy: inline-policy-1"
  assert_contains "$output" "✅ Deleted inline policy: inline-policy-1"
  assert_contains "$output" "📝 Deleting IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "✅ IAM role deletion completed"
}

# =============================================================================
# Test: Success flow with multiple managed policies
# =============================================================================
@test "delete_role: detaches multiple managed policies" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
        ;;
      *"iam list-attached-role-policies"*)
        echo -e "arn:aws:iam::aws:policy/Policy1\tarn:aws:iam::aws:policy/Policy2"
        ;;
      *"iam detach-role-policy"*)
        return 0
        ;;
      *"iam list-role-policies"*)
        echo ""
        ;;
      *"iam delete-role"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Detaching managed policies..."
  assert_contains "$output" "📋 Detaching policy: arn:aws:iam::aws:policy/Policy1"
  assert_contains "$output" "✅ Detached policy: arn:aws:iam::aws:policy/Policy1"
  assert_contains "$output" "📋 Detaching policy: arn:aws:iam::aws:policy/Policy2"
  assert_contains "$output" "✅ Detached policy: arn:aws:iam::aws:policy/Policy2"
}

# =============================================================================
# Test: Success flow with multiple inline policies
# =============================================================================
@test "delete_role: deletes multiple inline policies" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
        ;;
      *"iam list-attached-role-policies"*)
        echo ""
        ;;
      *"iam list-role-policies"*)
        echo -e "inline-1\tinline-2"
        ;;
      *"iam delete-role-policy"*)
        return 0
        ;;
      *"iam delete-role"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Deleting inline policy: inline-1"
  assert_contains "$output" "✅ Deleted inline policy: inline-1"
  assert_contains "$output" "📋 Deleting inline policy: inline-2"
  assert_contains "$output" "✅ Deleted inline policy: inline-2"
}

# =============================================================================
# Test: No policies to detach or delete
# =============================================================================
@test "delete_role: no policies proceeds directly to role deletion" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
        ;;
      *"iam list-attached-role-policies"*)
        echo ""
        ;;
      *"iam list-role-policies"*)
        echo ""
        ;;
      *"iam delete-role"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Detaching managed policies..."
  assert_contains "$output" "📝 Deleting inline policies..."
  assert_contains "$output" "📝 Deleting IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "✅ IAM role deletion completed"
}

# =============================================================================
# Test: Role deletion fails
# =============================================================================
@test "delete_role: role deletion failure logs warning but does not fail" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
        ;;
      *"iam list-attached-role-policies"*)
        echo ""
        ;;
      *"iam list-role-policies"*)
        echo ""
        ;;
      *"iam delete-role"*)
        echo "An error occurred (DeleteConflict)" >&2
        return 1
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Deleting IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "⚠️  Failed to delete IAM role 'test-prefix-test-scope-123'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The role may still have attached policies, instance profiles, or was already deleted"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check attached policies: aws iam list-attached-role-policies --role-name test-prefix-test-scope-123"
  assert_contains "$output" "• Check instance profiles: aws iam list-instance-profiles-for-role --role-name test-prefix-test-scope-123"
  assert_contains "$output" "✅ IAM role deletion completed"
}
