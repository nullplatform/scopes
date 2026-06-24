#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/utils/assume_role — sourceable sts:AssumeRole step.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/utils/assume_role"
  # Each test runs under `bash -c` with a fresh PATH that puts our fakes first.
  export BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN_DIR"
}

teardown() {
  unset SECRET_MANAGER_ASSUME_ROLE_ARN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

@test "assume_role: no-op when SECRET_MANAGER_ASSUME_ROLE_ARN is empty" {
  unset SECRET_MANAGER_ASSUME_ROLE_ARN

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
# Mock: only handle 'sts assume-role'
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

  export SECRET_MANAGER_ASSUME_ROLE_ARN="arn:aws:iam::1:role/test"
  export SCOPE_ID="scope-42"

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

@test "assume_role: returns 1 when aws sts assume-role fails" {
  cat > "$BIN_DIR/aws" << 'EOF'
#!/bin/bash
echo "AccessDenied: not allowed" >&2
exit 255
EOF
  chmod +x "$BIN_DIR/aws"

  export SECRET_MANAGER_ASSUME_ROLE_ARN="arn:aws:iam::1:role/test"

  # Source in a subshell — `return 1` from sourced script becomes exit 1
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

  export SECRET_MANAGER_ASSUME_ROLE_ARN="arn:aws:iam::1:role/test"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  [ "$status" -ne 0 ]
  assert_contains "$output" "incomplete credentials"
}
