#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# Unit tests for parameters/utils/assume_role_step — orchestrates:
#   caller sets ASSUME_ROLE_SELECTOR + ASSUME_ROLE_OVERRIDE_ENV +
#     ASSUME_ROLE_DEFAULT_ENV →
#   resolve NRN + dimensions from CONTEXT →
#   np provider list (identity-access-control) →
#   resolve ARN via lib →
#   source assume_role (sts:AssumeRole).
#
# Provider-agnostic — the same step is sourced by aws-secrets-manager AND
# parameter_store with different selector + env names.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/utils/assume_role_step"
  export BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN_DIR"

  # aws mock — captures sts args, returns valid creds
  cat > "$BIN_DIR/aws" << 'EOF'
#!/bin/bash
echo "$@" >> "$AWS_INVOKED_LOG"
cat << 'JSON'
{"Credentials":{"AccessKeyId":"AKIA","SecretAccessKey":"sk","SessionToken":"t","Expiration":"2026-01-01T00:00:00Z"}}
JSON
EOF
  chmod +x "$BIN_DIR/aws"
  export AWS_INVOKED_LOG="$BATS_TEST_TMPDIR/aws-calls.log"
  : > "$AWS_INVOKED_LOG"

  # default np mock — replaced per-test
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "np $*" >> "$NP_INVOKED_LOG"
echo '{"results":[]}'
EOF
  chmod +x "$BIN_DIR/np"
  export NP_INVOKED_LOG="$BATS_TEST_TMPDIR/np-calls.log"
  : > "$NP_INVOKED_LOG"
}

teardown() {
  unset CONTEXT SCOPE_ID \
    ASSUME_ROLE_SELECTOR ASSUME_ROLE_OVERRIDE_ENV ASSUME_ROLE_DEFAULT_ENV \
    ASSUME_ROLE_SESSION_PREFIX ASSUME_ROLE_ARN_RESOLVED \
    SECRET_MANAGER_ASSUME_ROLE_ARN SECRET_MANAGER_ASSUME_ROLE_ARN_DEFAULT \
    PARAMETER_STORE_ASSUME_ROLE_ARN PARAMETER_STORE_ASSUME_ROLE_ARN_DEFAULT \
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

make_ctx() {
  local nrn="$1" dims="$2" scope_id="$3"
  jq -nc \
    --arg nrn "$nrn" \
    --argjson dims "${dims:-null}" \
    --arg scope_id "$scope_id" \
    '{scope:{nrn:$nrn, id:$scope_id}, dimensions:$dims}'
}

# Standard caller config for "aws-secrets-manager"-style tests.
SM_CALLER='ASSUME_ROLE_SELECTOR=secret_manager; ASSUME_ROLE_OVERRIDE_ENV=SECRET_MANAGER_ASSUME_ROLE_ARN; ASSUME_ROLE_DEFAULT_ENV=SECRET_MANAGER_ASSUME_ROLE_ARN_DEFAULT'

# ---- Contract: caller must set the three required vars ---------------------

@test "step: fails fast when ASSUME_ROLE_SELECTOR is missing" {
  export CONTEXT='{}'
  unset ASSUME_ROLE_SELECTOR

  run -127 bash -c "
    export PATH=$BIN_DIR:\$PATH
    ASSUME_ROLE_OVERRIDE_ENV=X ASSUME_ROLE_DEFAULT_ENV=Y
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_contains "$output" "ASSUME_ROLE_SELECTOR must be set"
}

@test "step: fails fast when ASSUME_ROLE_OVERRIDE_ENV is missing" {
  export CONTEXT='{}'

  run -127 bash -c "
    export PATH=$BIN_DIR:\$PATH
    ASSUME_ROLE_SELECTOR=secret_manager ASSUME_ROLE_DEFAULT_ENV=Y
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_contains "$output" "ASSUME_ROLE_OVERRIDE_ENV must be set"
}

@test "step: fails fast when ASSUME_ROLE_DEFAULT_ENV is missing" {
  export CONTEXT='{}'

  run -127 bash -c "
    export PATH=$BIN_DIR:\$PATH
    ASSUME_ROLE_SELECTOR=secret_manager ASSUME_ROLE_OVERRIDE_ENV=X
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_contains "$output" "ASSUME_ROLE_DEFAULT_ENV must be set"
}

# ---- Resolution flow -------------------------------------------------------

@test "step: secret_manager caller — override env wins, np is not called" {
  export CONTEXT="$(make_ctx "" "" "")"  # no NRN → no np lookup anyway
  export SECRET_MANAGER_ASSUME_ROLE_ARN="arn:from-env-sm"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$ASSUME_ROLE_ARN_RESOLVED
  "

  assert_equal "$status" "0"
  assert_contains "$output" "ARN=arn:from-env-sm"
  run cat "$AWS_INVOKED_LOG"
  assert_contains "$output" "--role-arn arn:from-env-sm"
}

@test "step: parameter_store caller — uses ITS OWN env var (not secret_manager's)" {
  export CONTEXT="$(make_ctx "" "" "")"
  export PARAMETER_STORE_ASSUME_ROLE_ARN="arn:ps-env"
  # secret_manager's env is also set — must be IGNORED
  export SECRET_MANAGER_ASSUME_ROLE_ARN="arn:sm-MUST-NOT-BE-USED"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    ASSUME_ROLE_SELECTOR=parameter_store
    ASSUME_ROLE_OVERRIDE_ENV=PARAMETER_STORE_ASSUME_ROLE_ARN
    ASSUME_ROLE_DEFAULT_ENV=PARAMETER_STORE_ASSUME_ROLE_ARN_DEFAULT
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$ASSUME_ROLE_ARN_RESOLVED
  "

  assert_contains "$output" "ARN=arn:ps-env"
  run cat "$AWS_INVOKED_LOG"
  assert_contains "$output" "--role-arn arn:ps-env"
}

@test "step: NRN-only lookup (no dimensions) — np called without --dimensions" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "np $*" >> "$NP_INVOKED_LOG"
cat << 'JSON'
{"results":[{"id":"prov-1","attributes":{"iam_role_arns":{"arns":[
  {"selector":"secret_manager","arn":"arn:from-provider"}
]}}}]}
JSON
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx "organization=acme:account=prod" "" "")"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$ASSUME_ROLE_ARN_RESOLVED
  "

  assert_contains "$output" "ARN=arn:from-provider"
  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "provider list --categories identity-access-control --nrn organization=acme:account=prod --format json"
  case "$output" in *"--dimensions"*) return 1 ;; esac
}

@test "step: parameter_store selector picks parameter_store ARN from provider" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
cat << 'JSON'
{"results":[{"id":"p","attributes":{"iam_role_arns":{"arns":[
  {"selector":"secret_manager","arn":"arn:sm"},
  {"selector":"parameter_store","arn":"arn:ps"}
]}}}]}
JSON
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx "org=acme" "" "")"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    ASSUME_ROLE_SELECTOR=parameter_store
    ASSUME_ROLE_OVERRIDE_ENV=PARAMETER_STORE_ASSUME_ROLE_ARN
    ASSUME_ROLE_DEFAULT_ENV=PARAMETER_STORE_ASSUME_ROLE_ARN_DEFAULT
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$ASSUME_ROLE_ARN_RESOLVED
  "

  assert_contains "$output" "ARN=arn:ps"
}

@test "step: CONTEXT.dimensions are passed as dim1:val1,dim2:val2 to np" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "np $*" >> "$NP_INVOKED_LOG"
echo '{"results":[]}'
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx "org=acme" '{"environment":"prod","region":"us-east-1"}' "")"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "--dimensions environment:prod,region:us-east-1"
  assert_contains "$output" "--nrn org=acme"
}

@test "step: dimensions absent → fall back to np scope read" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "np $*" >> "$NP_INVOKED_LOG"
if [ "$1" = "scope" ] && [ "$2" = "read" ]; then
  echo '{"environment":"staging"}'
else
  echo '{"results":[]}'
fi
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx "org=acme" "" "scope-uuid-1")"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "scope read --id scope-uuid-1 --format json --query .dimensions"
  assert_contains "$output" "--dimensions environment:staging"
}

@test "step: no NRN → skip np lookup, no ARN, no aws call (agent creds)" {
  export CONTEXT='{}'

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=[\$ASSUME_ROLE_ARN_RESOLVED]
  "

  assert_equal "$status" "0"
  assert_contains "$output" "ARN=[]"
  run cat "$NP_INVOKED_LOG"
  [ -z "$output" ]
  run cat "$AWS_INVOKED_LOG"
  [ -z "$output" ]
}

@test "step: session prefix flows through to assume_role" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
cat << 'JSON'
{"results":[{"id":"p","attributes":{"iam_role_arns":{"arns":[
  {"selector":"secret_manager","arn":"arn:x"}
]}}}]}
JSON
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx "org=acme" "" "scope-7")"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    ASSUME_ROLE_SESSION_PREFIX=np-secret-manager
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  run cat "$AWS_INVOKED_LOG"
  assert_contains "$output" "--role-session-name np-secret-manager-scope-7"
}
