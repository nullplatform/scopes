#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/secret_manager/store
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/secret_manager/store"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/uuidgen" << 'EOF'
#!/bin/bash
echo "fixed-sm-uuid"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/uuidgen"

  export AWS_LOG="$BATS_TEST_TMPDIR/aws.log"
  cat > "$BATS_TEST_TMPDIR/bin/aws" << EOF
#!/bin/bash
echo "ARGS: \$@" >> "$AWS_LOG"
if [ "\${MOCK_AWS_EXIT:-0}" -ne 0 ]; then exit \$MOCK_AWS_EXIT; fi
# create-secret returns ARN
echo "arn:aws:secretsmanager:us-east-1:111122223333:secret:parameters/fixed-sm-uuid-AbCdEf"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/aws"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export AWS_REGION="us-east-1"
  export SM_NAME_PREFIX="parameters/"
  export SM_KMS_KEY_ID=""
  export PARAMETER_ID=42
  export PARAMETER_VALUE="my-secret"

  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "secret_manager store: outputs external_id and metadata" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  secret_name=$(echo "$output" | jq -r '.metadata.secret_name')
  secret_arn=$(echo "$output" | jq -r '.metadata.secret_arn')
  region=$(echo "$output" | jq -r '.metadata.region')
  assert_equal "$external_id" "fixed-sm-uuid"
  assert_equal "$secret_name" "parameters/fixed-sm-uuid"
  assert_contains "$secret_arn" "arn:aws:secretsmanager"
  assert_equal "$region" "us-east-1"
}

@test "secret_manager store: calls aws secretsmanager create-secret with correct args" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "secretsmanager create-secret"
  assert_contains "$captured" "--region us-east-1"
  assert_contains "$captured" "--name parameters/fixed-sm-uuid"
}

@test "secret_manager store: includes --kms-key-id when SM_KMS_KEY_ID is set" {
  export SM_KMS_KEY_ID="alias/my-key"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "--kms-key-id alias/my-key"
}

@test "secret_manager store: omits --kms-key-id when SM_KMS_KEY_ID is empty" {
  export SM_KMS_KEY_ID=""

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  [[ "$captured" != *"--kms-key-id"* ]]
}

@test "secret_manager store: fails with troubleshooting when aws CLI fails" {
  run bash -c "$DEPS; MOCK_AWS_EXIT=1 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store parameter in AWS Secrets Manager"
  assert_contains "$output" "💡 Possible causes:"
}

@test "secret_manager store: honors custom SM_NAME_PREFIX" {
  export SM_NAME_PREFIX="custom-prefix/sub/"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "--name custom-prefix/sub/fixed-sm-uuid"
}
