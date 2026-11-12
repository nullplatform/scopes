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

  kubectl() {
    return 0
  }
  export -f kubectl

  # Mock rm
  rm() {
    command rm "$@" 2>/dev/null || true
  }
  export -f rm
}

teardown() {
  rm -rf "$OUTPUT_DIR" 2>/dev/null || true
  unset -f aws kubectl rm 2>/dev/null || true
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

recording_aws() {
  export AWS_LOG="$OUTPUT_DIR/aws.log"
  export TRUST_POLICY_COPY="$OUTPUT_DIR/trust-policy-copy.json"
  aws() {
    echo "$*" >> "$AWS_LOG"
    local previous="" arg
    for arg in "$@"; do
      if [ "$previous" = "--assume-role-policy-document" ]; then
        command cp "${arg#file://}" "$TRUST_POLICY_COPY"
      fi
      previous="$arg"
    done
    case "$*" in
      *"eks describe-cluster"*"cluster.identity.oidc.issuer"*)
        echo "https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEF1234567890" ;;
      *"eks describe-cluster"*"cluster.arn"*)
        echo "arn:aws:eks:us-east-1:123456789012:cluster/test-cluster" ;;
      *"sts get-caller-identity"*)
        echo "123456789012" ;;
      *"iam create-role"*)
        echo '{"Role": {"Arn": "arn:aws:iam::123456789012:role/nullplatform/custom-scopes/test-prefix-test-scope-123"}}' ;;
      *"eks create-pod-identity-association"*)
        echo '{"association": {"associationId": "a-abc123"}}' ;;
      *)
        return 0 ;;
    esac
  }
  export -f aws
}

@test "create_role: a pattern prefix names the role and the trusted service account from the context" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "{.account.slug}-{.namespace.slug}", "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Creating IAM role: test-account-test-namespace-test-scope-123"
  assert_contains "$(cat "$AWS_LOG")" "--role-name test-account-test-namespace-test-scope-123"
  assert_equal "$(jq -r '.Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/ABCDEF1234567890:sub"]' "$TRUST_POLICY_COPY")" \
    "system:serviceaccount:test-ns:test-account-test-namespace-test-scope-123"
}

@test "create_role: a prefix that cannot be rendered fails before creating the role" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "{.account.slug | ascii}", "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Could not render the IAM role name from prefix '{.account.slug | ascii}'"
  if grep -q "iam create-role" "$AWS_LOG" 2>/dev/null; then created="true"; else created="false"; fi
  assert_false "$created" "role created"
}

@test "create_role: additional tags are added to the role, rendering the patterned ones" {
  recording_aws
  export IAM='{
    "ENABLED": "true",
    "PREFIX": "test-prefix",
    "TAGS": {"team": "{.namespace.slug}", "owner": "{.account.slug}-{.application.slug}", "CostCenter": "CC 1234/Payments"},
    "ROLE": {"POLICIES": []}
  }'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Adding tag: team=test-namespace"
  assert_contains "$output" "📋 Adding tag: owner=test-account-test-app"
  assert_contains "$output" "📋 Adding tag: CostCenter=CC 1234/Payments"
  create_call="$(grep "iam create-role" "$AWS_LOG")"
  assert_contains "$create_call" "Key=team,Value=test-namespace"
  assert_contains "$create_call" "Key=owner,Value=test-account-test-app"
  assert_contains "$create_call" "Key=CostCenter,Value=CC 1234/Payments"
  assert_contains "$create_call" "Key=nullplatform,Value=true"
}

@test "create_role: an additional tag that redefines a nullplatform tag fails" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "TAGS": {"scope_id": "mine"}, "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Tag 'scope_id' in IAM.TAGS is already set by nullplatform"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Rename or remove 'scope_id' from IAM.TAGS"
}

@test "create_role: an additional tag with characters AWS rejects fails" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "TAGS": {"owners": "alice,bob"}, "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Tag 'owners' in IAM.TAGS has an invalid key or value 'alice,bob'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Use letters, digits, spaces and _ . : / = + - @ (keys up to 128 characters, values up to 256), and do not start a key with aws:"
}

@test "create_role: an additional tag whose pattern cannot be rendered fails" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "TAGS": {"team": "{.namespace.missing}"}, "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Naming path {.namespace.missing} resolves to an empty value"
  assert_contains "$output" "❌ Could not render tag 'team' from pattern '{.namespace.missing}'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Fix IAM.TAGS; see k8s/docs/resource-naming.md"
}

@test "create_role: an unknown IAM mode fails before creating anything" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "MODE": "", "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Invalid IAM mode ''"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Set IAM.MODE to irsa or pod_identity, or remove it to use irsa"
  assert_empty "$(cat "$AWS_LOG" 2>/dev/null)"
}

@test "create_role: pod_identity trusts the EKS Pod Identity service for this cluster and skips OIDC" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "MODE": "pod_identity", "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Getting EKS cluster ARN for cluster: test-cluster"
  if grep -q "cluster.identity.oidc.issuer" "$AWS_LOG"; then oidc="true"; else oidc="false"; fi
  assert_false "$oidc" "OIDC issuer requested"
  assert_equal "$(jq -r '.Statement[0].Principal.Service' "$TRUST_POLICY_COPY")" "pods.eks.amazonaws.com"
  assert_equal "$(jq -c '.Statement[0].Action' "$TRUST_POLICY_COPY")" '["sts:AssumeRole","sts:TagSession"]'
  assert_equal "$(jq -r '.Statement[0].Condition.StringEquals["aws:SourceAccount"]' "$TRUST_POLICY_COPY")" "123456789012"
  assert_equal "$(jq -r '.Statement[0].Condition.ArnEquals["aws:SourceArn"]' "$TRUST_POLICY_COPY")" "arn:aws:eks:us-east-1:123456789012:cluster/test-cluster"
}

@test "create_role: pod_identity associates the role with the scope service account, with the role tags" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "MODE": "pod_identity", "TAGS": {"team": "{.namespace.slug}"}, "ROLE": {"POLICIES": [{"TYPE": "arn", "VALUE": "arn:aws:iam::aws:policy/ReadOnlyAccess"}]}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Creating pod identity association for service account: test-ns/test-prefix-test-scope-123"
  assert_contains "$output" "✅ Pod identity association created successfully"
  association_call="$(grep "eks create-pod-identity-association" "$AWS_LOG")"
  assert_contains "$association_call" "--cluster-name test-cluster"
  assert_contains "$association_call" "--namespace test-ns"
  assert_contains "$association_call" "--service-account test-prefix-test-scope-123"
  assert_contains "$association_call" "--role-arn arn:aws:iam::123456789012:role/nullplatform/custom-scopes/test-prefix-test-scope-123"
  assert_contains "$association_call" '"team":"test-namespace"'
  assert_contains "$association_call" '"scope_id":"scope-1"'
  attach_line=$(grep -n "iam attach-role-policy" "$AWS_LOG" | cut -d: -f1)
  association_line=$(grep -n "eks create-pod-identity-association" "$AWS_LOG" | cut -d: -f1)
  [ "$attach_line" -lt "$association_line" ]
}

@test "create_role: irsa does not create a pod identity association" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "MODE": "irsa", "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  if grep -q "pod-identity-association" "$AWS_LOG"; then associated="true"; else associated="false"; fi
  assert_false "$associated" "pod identity association created"
}

@test "create_role: pod_identity cluster lookup failure shows error with hints" {
  recording_aws
  aws() {
    case "$*" in
      *"eks describe-cluster"*)
        echo "An error occurred (ResourceNotFoundException)" >&2
        return 1 ;;
    esac
  }
  export -f aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "MODE": "pod_identity", "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to get the ARN of EKS cluster 'test-cluster': An error occurred (ResourceNotFoundException)"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The cluster name may be wrong or the agent lacks eks:DescribeCluster"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify the cluster exists: aws eks describe-cluster --name test-cluster"
}

@test "create_role: pod_identity association failure shows error with hints" {
  recording_aws
  aws() {
    case "$*" in
      *"eks describe-cluster"*) echo "arn:aws:eks:us-east-1:123456789012:cluster/test-cluster" ;;
      *"sts get-caller-identity"*) echo "123456789012" ;;
      *"iam create-role"*) echo '{"Role": {"Arn": "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"}}' ;;
      *"eks create-pod-identity-association"*)
        echo "An error occurred (AccessDeniedException)" >&2
        return 1 ;;
    esac
  }
  export -f aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "MODE": "pod_identity", "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to create pod identity association for 'test-ns/test-prefix-test-scope-123': An error occurred (AccessDeniedException)"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The association may already exist or the agent lacks eks:CreatePodIdentityAssociation or iam:PassRole"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check existing associations: aws eks list-pod-identity-associations --cluster-name test-cluster --namespace test-ns"
  assert_contains "$output" "• Verify the agent role can pass roles under /nullplatform/custom-scopes/"
}

@test "create_role: an additional tag that redefines a nullplatform tag in another case fails" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "TAGS": {"Scope": "mine"}, "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Tag 'Scope' in IAM.TAGS is already set by nullplatform"
}

@test "create_role: an additional tag with the reserved aws: prefix fails" {
  recording_aws
  export IAM='{"ENABLED": "true", "PREFIX": "test-prefix", "TAGS": {"AWS:owner": "me"}, "ROLE": {"POLICIES": []}}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Tag 'AWS:owner' in IAM.TAGS has an invalid key or value 'me'"
  assert_contains "$output" "• Use letters, digits, spaces and _ . : / = + - @ (keys up to 128 characters, values up to 256), and do not start a key with aws:"
}
