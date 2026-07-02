#!/usr/bin/env bats
# =============================================================================
# Unit tests for iam/create_role - IAM role creation with policies
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  # Script under test
  export SCRIPT="$BATS_TEST_DIRNAME/../../iam/create_role"

  # Default environment variables
  export SCOPE_ID="test-scope-123"
  export CLUSTER_NAME="test-cluster"
  export OUTPUT_DIR="$(mktemp -d)"
  export CONTEXT='{
    "k8s_namespace": "test-ns",
    "application": {"id": "app-1", "slug": "test-app"},
    "scope": {"id": "scope-1", "slug": "test-scope", "dimensions": null},
    "account": {"id": "acc-1", "slug": "test-account", "organization_id": "org-1"},
    "namespace": {"id": "ns-1", "slug": "test-namespace"}
  }'

  # Mock aws - default success
  aws() {
    case "$*" in
      *"eks describe-cluster"*)
        echo "https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEF1234567890"
        ;;
      *"sts get-caller-identity"*)
        echo "123456789012"
        ;;
      *"iam create-role"*)
        echo '{"Role": {"Arn": "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"}}'
        ;;
      *"iam attach-role-policy"*)
        return 0
        ;;
      *"iam put-role-policy"*)
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws

  # Mock rm
  rm() {
    command rm "$@" 2>/dev/null || true
  }
  export -f rm
}

teardown() {
  rm -rf "$OUTPUT_DIR" 2>/dev/null || true
  unset -f aws rm 2>/dev/null || true
}

# =============================================================================
# Test: IAM disabled (ENABLED=false) skips role setup
# =============================================================================
@test "create_role: IAM disabled (ENABLED=false) skips with message" {
  export IAM='{"ENABLED":"false"}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping role creation"
}

# =============================================================================
# Test: IAM disabled (ENABLED=null) skips role setup
# =============================================================================
@test "create_role: IAM disabled (ENABLED=null) skips with message" {
  export IAM='{"ENABLED":null}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping role creation"
}

# =============================================================================
# Test: IAM not set defaults to empty JSON and skips
# =============================================================================
@test "create_role: IAM not set defaults to empty JSON and skips" {
  unset IAM

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping role creation"
}

# =============================================================================
# Test: Success flow with boundary and managed policy
# =============================================================================
@test "create_role: success flow with boundary and managed policy" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": "arn:aws:iam::123456789012:policy/boundary",
      "POLICIES": [
        {"TYPE": "arn", "VALUE": "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"}
      ]
    }
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Getting EKS OIDC provider for cluster: test-cluster"
  assert_contains "$output" "🔍 Getting AWS account ID..."
  assert_contains "$output" "📝 Creating IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "📋 Using permissions boundary: arn:aws:iam::123456789012:policy/boundary"
  assert_contains "$output" "✅ IAM role created successfully"
  assert_contains "$output" "📋 Processing policy 1: Type=arn"
  assert_contains "$output" "📝 Attaching managed policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  assert_contains "$output" "✅ Successfully attached managed policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# =============================================================================
# Test: Success flow without boundary
# =============================================================================
@test "create_role: success flow without boundary creates role without permissions-boundary" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": null,
      "POLICIES": []
    }
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Getting EKS OIDC provider for cluster: test-cluster"
  assert_contains "$output" "🔍 Getting AWS account ID..."
  assert_contains "$output" "📝 Creating IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "✅ IAM role created successfully"
}

# =============================================================================
# Test: Error - aws eks describe-cluster fails
# =============================================================================
@test "create_role: aws eks describe-cluster failure shows error with hints" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {"BOUNDARY_ARN": null, "POLICIES": []}
  }'

  aws() {
    case "$*" in
      *"eks describe-cluster"*)
        echo "An error occurred (ResourceNotFoundException) when calling the DescribeCluster operation" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "🔍 Getting EKS OIDC provider for cluster: test-cluster"
  assert_contains "$output" "❌ Failed to get OIDC provider for EKS cluster 'test-cluster'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The OIDC provider may not be configured for this EKS cluster"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify OIDC is enabled: aws eks describe-cluster --name test-cluster --query cluster.identity.oidc"
  assert_contains "$output" "• Enable OIDC provider: eksctl utils associate-iam-oidc-provider --cluster test-cluster --approve"
}

# =============================================================================
# Test: Error - aws sts get-caller-identity fails
# =============================================================================
@test "create_role: aws sts get-caller-identity failure shows error with hints" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {"BOUNDARY_ARN": null, "POLICIES": []}
  }'

  aws() {
    case "$*" in
      *"eks describe-cluster"*)
        echo "https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEF1234567890"
        ;;
      *"sts get-caller-identity"*)
        echo "Unable to locate credentials" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "🔍 Getting EKS OIDC provider for cluster: test-cluster"
  assert_contains "$output" "🔍 Getting AWS account ID..."
  assert_contains "$output" "❌ Failed to get AWS account ID"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "AWS credentials may not be configured or have expired"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check AWS credentials: aws sts get-caller-identity"
  assert_contains "$output" "• Verify IAM permissions for the agent role"
}

# =============================================================================
# Test: Managed policy attachment (type=arn) with success message
# =============================================================================
@test "create_role: managed policy attachment logs processing and success" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": null,
      "POLICIES": [
        {"TYPE": "arn", "VALUE": "arn:aws:iam::aws:policy/ReadOnlyAccess"}
      ]
    }
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Processing policy 1: Type=arn"
  assert_contains "$output" "📝 Attaching managed policy: arn:aws:iam::aws:policy/ReadOnlyAccess"
  assert_contains "$output" "✅ Successfully attached managed policy: arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# =============================================================================
# Test: Inline policy attachment (type=inline) with success message
# =============================================================================
@test "create_role: inline policy attachment logs processing and success" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": null,
      "POLICIES": [
        {"TYPE": "inline", "VALUE": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"*\"}]}"}
      ]
    }
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Processing policy 1: Type=inline"
  assert_contains "$output" "📝 Attaching inline policy: inline-policy-1"
  assert_contains "$output" "✅ Successfully attached inline policy: inline-policy-1"
}

# =============================================================================
# Test: Inline policy document is written under OUTPUT_DIR, not /tmp
# (regression: shared /tmp path collided across concurrent create_role runs)
# =============================================================================
@test "create_role: inline policy document is written under OUTPUT_DIR" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": null,
      "POLICIES": [
        {"TYPE": "inline", "VALUE": "{\"Version\":\"2012-10-17\",\"Statement\":[]}"}
      ]
    }
  }'

  aws() {
    case "$*" in
      *"eks describe-cluster"*)
        echo "https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEF1234567890"
        ;;
      *"sts get-caller-identity"*)
        echo "123456789012"
        ;;
      *"iam create-role"*)
        echo '{"Role": {"Arn": "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"}}'
        ;;
      *"iam put-role-policy"*)
        # Emit the args so the test can assert on the --policy-document path
        echo "PUT_ROLE_POLICY_ARGS: $*"
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "--policy-document file://$OUTPUT_DIR/inline-policy-0.json"

  # Guard against the shared /tmp path regression
  if echo "$output" | grep -q "file:///tmp/inline-policy"; then
    uses_tmp="true"
  else
    uses_tmp="false"
  fi
  assert_false "$uses_tmp" "inline policy document under /tmp"
}

# =============================================================================
# Test: Unknown policy type shows warning
# =============================================================================
@test "create_role: unknown policy type shows warning message" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": null,
      "POLICIES": [
        {"TYPE": "unknown", "VALUE": "some-value"}
      ]
    }
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Processing policy 1: Type=unknown"
  assert_contains "$output" "⚠️  Unknown policy type: unknown, skipping"
}

# =============================================================================
# Test: Multiple policies of different types
# =============================================================================
@test "create_role: multiple policies are processed in order" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": null,
      "POLICIES": [
        {"TYPE": "arn", "VALUE": "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"},
        {"TYPE": "inline", "VALUE": "{\"Version\":\"2012-10-17\",\"Statement\":[]}"},
        {"TYPE": "unknown", "VALUE": "bad-type"}
      ]
    }
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Processing policy 1: Type=arn"
  assert_contains "$output" "📝 Attaching managed policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  assert_contains "$output" "✅ Successfully attached managed policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  assert_contains "$output" "📋 Processing policy 2: Type=inline"
  assert_contains "$output" "📝 Attaching inline policy: inline-policy-2"
  assert_contains "$output" "✅ Successfully attached inline policy: inline-policy-2"
  assert_contains "$output" "📋 Processing policy 3: Type=unknown"
  assert_contains "$output" "⚠️  Unknown policy type: unknown, skipping"
}

# =============================================================================
# Test: No policies to attach
# =============================================================================
@test "create_role: no policies skips policy attachment loop" {
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": null,
      "POLICIES": []
    }
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Getting EKS OIDC provider for cluster: test-cluster"
  assert_contains "$output" "🔍 Getting AWS account ID..."
  assert_contains "$output" "📝 Creating IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "✅ IAM role created successfully"
}

# =============================================================================
# Test: Context with dimensions adds tags
# =============================================================================
@test "create_role: context with dimensions processes correctly" {
  export CONTEXT='{
    "k8s_namespace": "test-ns",
    "application": {"id": "app-1", "slug": "test-app"},
    "scope": {"id": "scope-1", "slug": "test-scope", "dimensions": {"env": "production", "region": "us-east-1"}},
    "account": {"id": "acc-1", "slug": "test-account", "organization_id": "org-1"},
    "namespace": {"id": "ns-1", "slug": "test-namespace"}
  }'
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "ROLE": {
      "BOUNDARY_ARN": null,
      "POLICIES": []
    }
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Getting EKS OIDC provider for cluster: test-cluster"
  assert_contains "$output" "🔍 Getting AWS account ID..."
  assert_contains "$output" "📝 Creating IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "✅ IAM role created successfully"
}
