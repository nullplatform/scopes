#!/usr/bin/env bats
# =============================================================================
# Unit tests for utils/assume_role_step - resolves the role and assumes it.
#
# The IAM provider and scope-configurations provider are read from
# CONTEXT.providers[...] (already dimension-resolved by the platform), so the
# tests only need to mock `aws` (sts) — no np.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export STEP="$BATS_TEST_DIRNAME/../assume_role_step"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCOPE_ID="scope-123"
  # CONTEXT with the IAM provider (resolved) carrying a k8s role.
  export CONTEXT='{"providers":{"identity-access-control":{"iam_role_arns":{"arns":[{"selector":"k8s","arn":"arn:aws:iam::111:role/k8s-role"}]}}}}'
  unset ASSUME_ROLE_ARN ASSUME_ROLE_ARN_DEFAULT ASSUME_ROLE_SELECTOR

  aws() {
    case "$*" in
      *"sts assume-role"*) echo '{"Credentials":{"AccessKeyId":"AKIA1","SecretAccessKey":"sec1","SessionToken":"tok1"}}' ;;
      *) return 0 ;;
    esac
  }
  export -f aws
}

teardown() {
  unset ASSUME_ROLE_ARN ASSUME_ROLE_ARN_DEFAULT ASSUME_ROLE_SELECTOR
}

@test "assume_role_step: resolves the k8s role from CONTEXT and exports creds" {
  run bash -c "source '$STEP'; echo \"\$AWS_ACCESS_KEY_ID|\$ASSUME_ROLE_ARN\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "AKIA1|arn:aws:iam::111:role/k8s-role"
}

@test "assume_role_step: no IAM provider in CONTEXT is not an error (agent creds remain)" {
  export CONTEXT='{"providers":{}}'
  run bash -c "source '$STEP'; echo \"key=\${AWS_ACCESS_KEY_ID:-none} arn=[\${ASSUME_ROLE_ARN}]\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "key=none"
  assert_contains "$output" "arn=[]"
}

@test "assume_role_step: uses the dimension-resolved provider already in CONTEXT" {
  # The platform injects whichever IAM config matched the scope's dimensions;
  # the step just reads it. Here the resolved config carries a region-specific role.
  export CONTEXT='{"providers":{"identity-access-control":{"iam_role_arns":{"arns":[{"selector":"k8s","arn":"arn:aws:iam::111:role/us-east-1-role"}]}}}}'
  run bash -c "source '$STEP'; echo \"\$ASSUME_ROLE_ARN\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "arn:aws:iam::111:role/us-east-1-role"
}

@test "assume_role_step: honors ASSUME_ROLE_SELECTOR override" {
  export ASSUME_ROLE_SELECTOR="custom"
  export CONTEXT='{"providers":{"identity-access-control":{"iam_role_arns":{"arns":[{"selector":"custom","arn":"arn:aws:iam::111:role/custom-role"}]}}}}'
  run bash -c "source '$STEP'; echo \"\$ASSUME_ROLE_ARN\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "arn:aws:iam::111:role/custom-role"
}

@test "assume_role_step: falls back to scope-configurations assume_role.arn" {
  export CONTEXT='{"providers":{"scope-configurations":{"assume_role":{"arn":"arn:aws:iam::111:role/scope-cfg-role"}}}}'
  run bash -c "source '$STEP'; echo \"\$ASSUME_ROLE_ARN\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "arn:aws:iam::111:role/scope-cfg-role"
}

@test "assume_role_step: pre-set ASSUME_ROLE_ARN overrides provider resolution" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111:role/explicit-override"
  run bash -c "source '$STEP'; echo \"\$ASSUME_ROLE_ARN|\$AWS_ACCESS_KEY_ID\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "arn:aws:iam::111:role/explicit-override|AKIA1"
}

@test "assume_role_step: exits non-zero with hints when sts:AssumeRole fails" {
  aws() {
    case "$*" in
      *"sts assume-role"*) echo "AccessDenied" >&2; return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f aws
  run bash -c "source '$STEP'"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Possible causes"
}
