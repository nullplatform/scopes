#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/aws-secrets-manager/store
#
# Verifies:
#   - external_id composed from entities + dimensions + parameter_name-id
#   - Path prefix is `nullplatform/`
#   - First store uses CreateSecret with managed_by tag
#   - Subsequent stores (ResourceExistsException) fall through to PutSecretValue
#   - Payload includes managed_by: nullplatform
#   - Real errors propagate with troubleshooting
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_ROOT="$PARAMETERS_DIR"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/aws-secrets-manager/store"

  mkdir -p "$BATS_TEST_TMPDIR/bin"

  cat > "$BATS_TEST_TMPDIR/bin/np" << 'EOF'
#!/bin/bash
entity_type="$1"
case "$entity_type" in
  organization) echo "\"acme\"" ;;
  account)      echo "\"prod\"" ;;
  namespace)    echo "\"billing\"" ;;
  application)  echo "\"api\"" ;;
  *)            echo "\"unknown\"" ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/np"

  export AWS_LOG="$BATS_TEST_TMPDIR/aws.log"
  cat > "$BATS_TEST_TMPDIR/bin/aws" << 'EOF'
#!/bin/bash
echo "ARGS: $@" >> "$AWS_LOG"
mode="${MOCK_AWS_MODE:-success}"

if [[ "$*" == *"create-secret"* ]]; then
  case "$mode" in
    success)
      echo '{"ARN":"arn:aws:secretsmanager:us-east-1:111122223333:secret:nullplatform/test-AbCdEf","VersionId":"v1-create-uuid","Name":"nullplatform/test"}'
      exit 0
      ;;
    exists|put_error)
      echo "An error occurred (ResourceExistsException) when calling the CreateSecret operation: resource already exists." >&2
      exit 254
      ;;
    create_error)
      echo "An error occurred (AccessDeniedException) when calling the CreateSecret operation: not authorized." >&2
      exit 254
      ;;
  esac
elif [[ "$*" == *"put-secret-value"* ]]; then
  case "$mode" in
    exists)
      echo '{"ARN":"arn:aws:secretsmanager:us-east-1:111122223333:secret:nullplatform/test-AbCdEf","VersionId":"v2-put-uuid"}'
      exit 0
      ;;
    put_error)
      echo "An error occurred (AccessDeniedException) when calling the PutSecretValue operation: not authorized." >&2
      exit 254
      ;;
  esac
fi
exit 1
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/aws"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export AWS_REGION="us-east-1"
  export SM_NAME_PREFIX="nullplatform/"
  export SM_KMS_KEY_ID=""
  export PARAMETER_ID=42
  export PARAMETER_VALUE="my-secret"
  export CONTEXT='{
    "parameter_id": 42,
    "parameter_name": "DB_PASSWORD",
    "value": "my-secret",
    "entities": {
      "organization": "1255165411",
      "account": "95118862",
      "namespace": "37094320",
      "application": "321402625"
    },
    "dimensions": {}
  }'

  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "aws-secrets-manager store: external_id includes entities + parameter_name-id + version" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  expected="organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/DB_PASSWORD-42#v1-create-uuid"
  assert_equal "$external_id" "$expected"
}

@test "aws-secrets-manager store: secret_name uses nullplatform/ prefix" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  secret_name=$(echo "$output" | jq -r '.metadata.secret_name')
  assert_contains "$secret_name" "nullplatform/organization=acme-1255165411"
  assert_contains "$secret_name" "DB_PASSWORD-42"
}

@test "aws-secrets-manager store: first store uses CreateSecret with managed_by tag" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "secretsmanager create-secret"
  assert_contains "$captured" "--tags Key=managed_by,Value=nullplatform"
  [[ "$captured" != *"put-secret-value"* ]]
}

@test "aws-secrets-manager store: version_id is encoded as #suffix in external_id" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  version="${external_id##*#}"
  assert_equal "$version" "v1-create-uuid"
}

@test "aws-secrets-manager store: PutSecretValue's version_id replaces create's in external_id" {
  run bash -c "$DEPS; MOCK_AWS_MODE=exists source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  version="${external_id##*#}"
  assert_equal "$version" "v2-put-uuid"
}

@test "aws-secrets-manager store: ResourceExistsException falls through to PutSecretValue" {
  run bash -c "$DEPS; MOCK_AWS_MODE=exists source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "secretsmanager create-secret"
  assert_contains "$captured" "secretsmanager put-secret-value"
  assert_contains "$captured" "--secret-id nullplatform/organization=acme-1255165411"
}

@test "aws-secrets-manager store: PutSecretValue failure propagates with troubleshooting" {
  run bash -c "$DEPS; MOCK_AWS_MODE=put_error source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to add new version"
  assert_contains "$output" "secretsmanager:PutSecretValue"
  assert_contains "$output" "🔧 How to fix:"
}

@test "aws-secrets-manager store: non-exists create errors propagate with troubleshooting" {
  run bash -c "$DEPS; MOCK_AWS_MODE=create_error source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store parameter in AWS Secrets Manager"
  assert_contains "$output" "secretsmanager:CreateSecret"
}

@test "aws-secrets-manager store: includes --kms-key-id when SM_KMS_KEY_ID set" {
  export SM_KMS_KEY_ID="alias/my-key"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "--kms-key-id alias/my-key"
}

@test "aws-secrets-manager store: dimensions sort alphabetically in external_id" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.dimensions = {environment: "prod", country: "arg"}')

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  assert_contains "$external_id" "country=arg/environment=prod/DB_PASSWORD-42"
}
