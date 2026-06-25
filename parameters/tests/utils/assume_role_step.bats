#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# Unit tests for parameters/utils/assume_role_step — orchestrates:
#   caller sets ASSUME_ROLE_SELECTOR + ASSUME_ROLE_OVERRIDE_ENV +
#     ASSUME_ROLE_DEFAULT_ENV →
#   build NRN from CONTEXT.entities or CONTEXT.value_entities →
#   resolve dimensions from CONTEXT.dimensions (fallback: np scope read) →
#   np provider list (identity-access-control) →
#   resolve ARN via lib →
#   source assume_role (sts:AssumeRole).
#
# Provider-agnostic — the same step is sourced by aws-secrets-manager AND
# aws-parameter-store with different selector + env names.
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

# Build a CONTEXT mimicking the real platform notification body:
#   make_ctx [dims_json] [scope_id]
#     dims_json  — '{}' or '{"key":"val",...}'; empty/"" = no .dimensions
#     scope_id   — when non-empty, payload uses value_entities (with scope)
#                  instead of entities (so NRN gets the scope segment)
make_ctx() {
  local dims="$1" scope_id="$2"
  local dims_arg=""
  if [ -n "$dims" ]; then
    dims_arg="$dims"
  else
    dims_arg="null"
  fi
  if [ -n "$scope_id" ]; then
    jq -nc --arg s "$scope_id" --argjson dims "$dims_arg" \
      '{value_entities:{organization:"1255165411",account:"95118862",namespace:"1249051863",application:"2132488335",scope:$s}, dimensions:$dims}'
  else
    jq -nc --argjson dims "$dims_arg" \
      '{entities:{organization:"1255165411",account:"95118862",namespace:"1249051863",application:"2132488335"}, dimensions:$dims}'
  fi
}

# Caller bindings for each AWS provider's setup.
SM_CALLER='ASSUME_ROLE_SELECTOR=secret_manager; ASSUME_ROLE_OVERRIDE_ENV=SECRET_MANAGER_ASSUME_ROLE_ARN; ASSUME_ROLE_DEFAULT_ENV=SECRET_MANAGER_ASSUME_ROLE_ARN_DEFAULT'
PS_CALLER='ASSUME_ROLE_SELECTOR=parameter_store; ASSUME_ROLE_OVERRIDE_ENV=PARAMETER_STORE_ASSUME_ROLE_ARN; ASSUME_ROLE_DEFAULT_ENV=PARAMETER_STORE_ASSUME_ROLE_ARN_DEFAULT'

APP_NRN='organization=1255165411:account=95118862:namespace=1249051863:application=2132488335'

# ---- Contract: caller must set the three required vars ---------------------

@test "step: fails fast when ASSUME_ROLE_SELECTOR is missing" {
  export CONTEXT='{}'

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

# ---- NRN construction ------------------------------------------------------

@test "step: app-level — NRN from entities (no scope segment)" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "np $*" >> "$NP_INVOKED_LOG"
echo '{"results":[]}'
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx '' '')"  # entities only, no dimensions, no scope

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "--nrn $APP_NRN"
  case "$output" in *"--dimensions"*) return 1 ;; esac
  case "$output" in *":scope="*) return 1 ;; esac
}

@test "step: dimension-level — NRN from entities + dimensions passed to np" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "np $*" >> "$NP_INVOKED_LOG"
echo '{"results":[]}'
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx '{"country":"argentina","site":"aws-main"}' '')"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "--nrn $APP_NRN"
  assert_contains "$output" "--dimensions country:argentina,site:aws-main"
  case "$output" in *":scope="*) return 1 ;; esac
}

@test "step: scope-level — NRN from value_entities (includes :scope=… segment)" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "np $*" >> "$NP_INVOKED_LOG"
echo '{"results":[]}'
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx '' '601620319')"  # scope-level, no dimensions

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "--nrn $APP_NRN:scope=601620319"
}

@test "step: scope-level without top-level dimensions → np scope read fallback" {
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

  export CONTEXT="$(make_ctx '' '601620319')"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "scope read --id 601620319 --format json --query .dimensions"
  assert_contains "$output" "--dimensions environment:staging"
}

# ---- ARN resolution --------------------------------------------------------

@test "step: secret_manager caller — override env wins, np is not called" {
  export CONTEXT='{}'  # no entities → no IAM lookup, only env override matters
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
  export CONTEXT='{}'
  export PARAMETER_STORE_ASSUME_ROLE_ARN="arn:ps-env"
  export SECRET_MANAGER_ASSUME_ROLE_ARN="arn:sm-MUST-NOT-BE-USED"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $PS_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$ASSUME_ROLE_ARN_RESOLVED
  "

  assert_contains "$output" "ARN=arn:ps-env"
  run cat "$AWS_INVOKED_LOG"
  assert_contains "$output" "--role-arn arn:ps-env"
}

@test "step: provider lookup returns matching selector ARN" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
cat << 'JSON'
{"results":[{"id":"prov-1","attributes":{"iam_role_arns":{"arns":[
  {"selector":"secret_manager","arn":"arn:from-provider"}
]}}}]}
JSON
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx '' '')"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$ASSUME_ROLE_ARN_RESOLVED
  "

  assert_contains "$output" "ARN=arn:from-provider"
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

  export CONTEXT="$(make_ctx '' '')"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $PS_CALLER
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$ASSUME_ROLE_ARN_RESOLVED
  "

  assert_contains "$output" "ARN=arn:ps"
}

@test "step: no entities → skip np lookup, no ARN, no aws call (agent creds)" {
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

@test "step: session prefix flows through to assume_role with scope id" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
cat << 'JSON'
{"results":[{"id":"p","attributes":{"iam_role_arns":{"arns":[
  {"selector":"secret_manager","arn":"arn:x"}
]}}}]}
JSON
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx '' '601620319')"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    $SM_CALLER
    ASSUME_ROLE_SESSION_PREFIX=np-secret-manager
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  run cat "$AWS_INVOKED_LOG"
  assert_contains "$output" "--role-session-name np-secret-manager-601620319"
}
