#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/aws_secret_manager/store
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_ROOT="$PARAMETERS_DIR"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/aws_secret_manager/store"

  mkdir -p "$BATS_TEST_TMPDIR/bin"

  # Mock np CLI for entity slug fetches
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
  cat > "$BATS_TEST_TMPDIR/bin/aws" << EOF
#!/bin/bash
echo "ARGS: \$@" >> "$AWS_LOG"
if [ "\${MOCK_AWS_EXIT:-0}" -ne 0 ]; then exit \$MOCK_AWS_EXIT; fi
echo "arn:aws:secretsmanager:us-east-1:111122223333:secret:test-AbCdEf"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/aws"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export AWS_REGION="us-east-1"
  export SM_NAME_PREFIX="parameters/"
  export SM_KMS_KEY_ID=""
  export PARAMETER_ID=42
  export PARAMETER_VALUE="my-secret"
  export CONTEXT='{
    "parameter_id": 42,
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

@test "aws_secret_manager store: external_id is composite of entities + parameter_id" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  expected="organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/42"
  assert_equal "$external_id" "$expected"
}

@test "aws_secret_manager store: secret_name has prefix + composite" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  secret_name=$(echo "$output" | jq -r '.metadata.secret_name')
  assert_contains "$secret_name" "parameters/organization=acme-1255165411"
}

@test "aws_secret_manager store: calls aws with composite name" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "secretsmanager create-secret"
  assert_contains "$captured" "--region us-east-1"
  assert_contains "$captured" "--name parameters/organization=acme-1255165411"
}

@test "aws_secret_manager store: includes --kms-key-id when SM_KMS_KEY_ID set" {
  export SM_KMS_KEY_ID="alias/my-key"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "--kms-key-id alias/my-key"
}

@test "aws_secret_manager store: omits --kms-key-id when SM_KMS_KEY_ID empty" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  [[ "$captured" != *"--kms-key-id"* ]]
}

@test "aws_secret_manager store: dimensions sorted alphabetically in external_id" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.dimensions = {environment: "prod", country: "arg"}')

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  assert_contains "$external_id" "country=arg/environment=prod/42"
}

@test "aws_secret_manager store: fails with troubleshooting on aws error" {
  run bash -c "$DEPS; MOCK_AWS_EXIT=1 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store parameter in AWS Secrets Manager"
}
