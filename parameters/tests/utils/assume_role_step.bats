#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/utils/assume_role_step — orchestrates:
#   CONTEXT → resolve NRN + dimensions → np provider list →
#   resolve ARN → source assume_role (sts:AssumeRole).
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/utils/assume_role_step"
  export BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN_DIR"

  # A passthrough aws mock that records its sts call args.
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

  # Default `np` mock — replaced per-test as needed.
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
  unset SECRET_MANAGER_ASSUME_ROLE_ARN SECRET_MANAGER_ASSUME_ROLE_ARN_DEFAULT \
    SECRET_MANAGER_ASSUME_ROLE_SELECTOR CONTEXT SCOPE_ID \
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# Build a CONTEXT with overridable NRN / dimensions / scope.id.
make_ctx() {
  local nrn="$1" dims="$2" scope_id="$3"
  jq -nc \
    --arg nrn "$nrn" \
    --argjson dims "${dims:-null}" \
    --arg scope_id "$scope_id" \
    '{scope:{nrn:$nrn, id:$scope_id}, dimensions:$dims}'
}

@test "step: env override → np is not even called when ARN is preset" {
  export SECRET_MANAGER_ASSUME_ROLE_ARN="arn:aws:iam::1:role/from-env"
  export CONTEXT="$(make_ctx "" "" "")"  # empty NRN → np lookup skipped

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$SECRET_MANAGER_ASSUME_ROLE_ARN
  "

  assert_equal "$status" "0"
  assert_contains "$output" "ARN=arn:aws:iam::1:role/from-env"
  # aws sts assume-role WAS called with the env-set ARN
  run cat "$AWS_INVOKED_LOG"
  assert_contains "$output" "--role-arn arn:aws:iam::1:role/from-env"
}

@test "step: NRN-only lookup (no dimensions) — np is called without --dimensions" {
  # np mock that returns an IAM provider with secret_manager selector
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "np $*" >> "$NP_INVOKED_LOG"
cat << 'JSON'
{"results":[{"id":"prov-1","attributes":{"iam_role_arns":{"arns":[
  {"selector":"secret_manager","arn":"arn:aws:iam::1:role/from-provider"}
]}}}]}
JSON
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx "organization=acme:account=prod" "" "")"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$SECRET_MANAGER_ASSUME_ROLE_ARN
  "

  assert_equal "$status" "0"
  assert_contains "$output" "ARN=arn:aws:iam::1:role/from-provider"
  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "provider list --categories identity-access-control --nrn organization=acme:account=prod --format json"
  # No --dimensions flag
  refute_contains() { case "$1" in *"$2"*) return 1 ;; *) return 0 ;; esac; }
  refute_contains "$output" "--dimensions"
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
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "--dimensions environment:prod,region:us-east-1"
  assert_contains "$output" "--nrn org=acme"
}

@test "step: dimensions absent → fall back to np scope read" {
  # First np call = scope read (returns dimensions), second = provider list.
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
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_INVOKED_LOG"
  assert_contains "$output" "scope read --id scope-uuid-1 --format json --query .dimensions"
  assert_contains "$output" "--dimensions environment:staging"
}

@test "step: no NRN → skip np lookup, no ARN, no aws call (agent creds)" {
  export CONTEXT='{}'

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=[\$SECRET_MANAGER_ASSUME_ROLE_ARN]
  "

  assert_equal "$status" "0"
  assert_contains "$output" "ARN=[]"
  run cat "$NP_INVOKED_LOG"
  [ -z "$output" ]
  run cat "$AWS_INVOKED_LOG"
  [ -z "$output" ]
}

@test "step: selector defaults to 'secret_manager'" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
cat << 'JSON'
{"results":[{"id":"p","attributes":{"iam_role_arns":{"arns":[
  {"selector":"containers","arn":"arn:bad"},
  {"selector":"secret_manager","arn":"arn:good"}
]}}}]}
JSON
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx "org=acme" "" "")"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$SECRET_MANAGER_ASSUME_ROLE_ARN
  "

  assert_contains "$output" "ARN=arn:good"
}

@test "step: SECRET_MANAGER_ASSUME_ROLE_SELECTOR override changes which ARN is picked" {
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
cat << 'JSON'
{"results":[{"id":"p","attributes":{"iam_role_arns":{"arns":[
  {"selector":"secret_manager","arn":"arn:default"},
  {"selector":"custom","arn":"arn:custom"}
]}}}]}
JSON
EOF
  chmod +x "$BIN_DIR/np"

  export CONTEXT="$(make_ctx "org=acme" "" "")"
  export SECRET_MANAGER_ASSUME_ROLE_SELECTOR="custom"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo ARN=\$SECRET_MANAGER_ASSUME_ROLE_ARN
  "

  assert_contains "$output" "ARN=arn:custom"
}
