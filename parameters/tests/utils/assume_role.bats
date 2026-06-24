#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/utils/assume_role — sourceable sts:AssumeRole step.
# Reads ASSUME_ROLE_ARN_RESOLVED (provider-agnostic) set by assume_role_step.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/utils/assume_role"
  export BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN_DIR"
}

teardown() {
  unset ASSUME_ROLE_ARN_RESOLVED ASSUME_ROLE_SESSION_PREFIX \
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

@test "assume_role: no-op when ASSUME_ROLE_ARN_RESOLVED is empty" {
  unset ASSUME_ROLE_ARN_RESOLVED

  run bash -c "
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo AKID=[\${AWS_ACCESS_KEY_ID:-}]
  "

  assert_equal "$status" "0"
  assert_contains "$output" "AKID=[]"
}

@test "assume_role: success exports temp credentials and logs ✅" {
  cat > "$BIN_DIR/aws" << 'EOF'
#!/bin/bash
[ "$1 $2" = "sts assume-role" ] || { echo "unexpected: $*" >&2; exit 1; }
cat << 'JSON'
{
  "Credentials": {
    "AccessKeyId": "AKIA-TEST",
    "SecretAccessKey": "sk-test",
    "SessionToken": "token-test",
    "Expiration": "2026-01-01T00:00:00Z"
  }
}
JSON
EOF
  chmod +x "$BIN_DIR/aws"

  export ASSUME_ROLE_ARN_RESOLVED="arn:aws:iam::1:role/test"
  export SCOPE_ID="scope-42"
  export ASSUME_ROLE_SESSION_PREFIX="np-secret-manager"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo AKID=\$AWS_ACCESS_KEY_ID
    echo SECRET=\$AWS_SECRET_ACCESS_KEY
    echo TOKEN=\$AWS_SESSION_TOKEN
  "

  assert_equal "$status" "0"
  assert_contains "$output" "AKID=AKIA-TEST"
  assert_contains "$output" "SECRET=sk-test"
  assert_contains "$output" "TOKEN=token-test"
  assert_contains "$output" "🔑 Assuming role: arn:aws:iam::1:role/test"
  assert_contains "$output" "✅ Role assumed successfully"
}

@test "assume_role: session name uses ASSUME_ROLE_SESSION_PREFIX + SCOPE_ID" {
  export AWS_ARGS_LOG="$BATS_TEST_TMPDIR/aws-args"
  cat > "$BIN_DIR/aws" << 'EOF'
#!/bin/bash
echo "$*" > "$AWS_ARGS_LOG"
cat << 'JSON'
{"Credentials":{"AccessKeyId":"a","SecretAccessKey":"s","SessionToken":"t","Expiration":"2026-01-01T00:00:00Z"}}
JSON
EOF
  chmod +x "$BIN_DIR/aws"

  export ASSUME_ROLE_ARN_RESOLVED="arn:role/x"
  export SCOPE_ID="scp-99"
  export ASSUME_ROLE_SESSION_PREFIX="np-parameter-store"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$AWS_ARGS_LOG"
  assert_contains "$output" "--role-session-name np-parameter-store-scp-99"
}

@test "assume_role: session name falls back to 'np-parameters' when prefix unset" {
  export AWS_ARGS_LOG="$BATS_TEST_TMPDIR/aws-args"
  cat > "$BIN_DIR/aws" << 'EOF'
#!/bin/bash
echo "$*" > "$AWS_ARGS_LOG"
cat << 'JSON'
{"Credentials":{"AccessKeyId":"a","SecretAccessKey":"s","SessionToken":"t","Expiration":"2026-01-01T00:00:00Z"}}
JSON
EOF
  chmod +x "$BIN_DIR/aws"

  export ASSUME_ROLE_ARN_RESOLVED="arn:role/x"
  export SCOPE_ID="scp-1"
  unset ASSUME_ROLE_SESSION_PREFIX

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$AWS_ARGS_LOG"
  assert_contains "$output" "--role-session-name np-parameters-scp-1"
}

@test "assume_role: returns 1 when aws sts assume-role fails" {
  cat > "$BIN_DIR/aws" << 'EOF'
#!/bin/bash
echo "AccessDenied: not allowed" >&2
exit 255
EOF
  chmod +x "$BIN_DIR/aws"

  export ASSUME_ROLE_ARN_RESOLVED="arn:aws:iam::1:role/test"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ sts:AssumeRole failed"
  assert_contains "$output" "AccessDenied: not allowed"
}

@test "assume_role: fails when aws returns incomplete credentials" {
  cat > "$BIN_DIR/aws" << 'EOF'
#!/bin/bash
echo '{"Credentials":{"AccessKeyId":"AKIA","SecretAccessKey":"","SessionToken":""}}'
EOF
  chmod +x "$BIN_DIR/aws"

  export ASSUME_ROLE_ARN_RESOLVED="arn:aws:iam::1:role/test"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  [ "$status" -ne 0 ]
  assert_contains "$output" "incomplete credentials"
}
