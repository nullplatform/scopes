#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/parameter_store/store
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/parameter_store/store"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/uuidgen" << 'EOF'
#!/bin/bash
echo "fixed-ps-uuid"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/uuidgen"

  export AWS_LOG="$BATS_TEST_TMPDIR/aws.log"
  cat > "$BATS_TEST_TMPDIR/bin/aws" << EOF
#!/bin/bash
echo "ARGS: \$@" >> "$AWS_LOG"
exit \${MOCK_AWS_EXIT:-0}
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/aws"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export AWS_REGION="us-east-1"
  export PS_NAME_PREFIX="/nullplatform/parameters/"
  export PS_KMS_KEY_ID=""
  export PS_TIER="Standard"
  export PARAMETER_ID=42
  export PARAMETER_VALUE="my-value"

  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "parameter_store store: outputs external_id and metadata" {
  export PARAMETER_KIND="parameter"

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  parameter_name=$(echo "$output" | jq -r '.metadata.parameter_name')
  type=$(echo "$output" | jq -r '.metadata.type')
  assert_equal "$external_id" "fixed-ps-uuid"
  assert_equal "$parameter_name" "/nullplatform/parameters/fixed-ps-uuid"
  assert_equal "$type" "String"
}

@test "parameter_store store: kind=secret uses SecureString" {
  export PARAMETER_KIND="secret"

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  type=$(echo "$output" | jq -r '.metadata.type')
  assert_equal "$type" "SecureString"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "--type SecureString"
}

@test "parameter_store store: kind=parameter uses String" {
  export PARAMETER_KIND="parameter"

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "--type String"
  [[ "$captured" != *"SecureString"* ]]
}

@test "parameter_store store: includes --key-id for SecureString when PS_KMS_KEY_ID set" {
  export PARAMETER_KIND="secret"
  export PS_KMS_KEY_ID="alias/parameters-secure"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "--key-id alias/parameters-secure"
}

@test "parameter_store store: omits --key-id when PS_KMS_KEY_ID is empty (uses default aws/ssm)" {
  export PARAMETER_KIND="secret"
  export PS_KMS_KEY_ID=""

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  [[ "$captured" != *"--key-id"* ]]
}

@test "parameter_store store: never includes --key-id for String (kind=parameter)" {
  export PARAMETER_KIND="parameter"
  export PS_KMS_KEY_ID="alias/should-not-be-used"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  [[ "$captured" != *"--key-id"* ]]
}

@test "parameter_store store: passes tier flag" {
  export PARAMETER_KIND="parameter"
  export PS_TIER="Advanced"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "--tier Advanced"
}

@test "parameter_store store: calls put-parameter with name and value" {
  export PARAMETER_KIND="parameter"

  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$AWS_LOG")
  assert_contains "$captured" "ssm put-parameter"
  assert_contains "$captured" "--region us-east-1"
  assert_contains "$captured" "--name /nullplatform/parameters/fixed-ps-uuid"
  assert_contains "$captured" "--value my-value"
}

@test "parameter_store store: fails with troubleshooting on aws error" {
  export PARAMETER_KIND="parameter"

  run bash -c "$DEPS; MOCK_AWS_EXIT=1 source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store parameter in AWS Parameter Store"
  assert_contains "$output" "💡 Possible causes:"
}
