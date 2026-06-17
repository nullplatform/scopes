#!/usr/bin/env bats
# =============================================================================
# Unit tests for utils/assume_role_step - resolves the role and assumes it
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export STEP="$BATS_TEST_DIRNAME/../assume_role_step"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCOPE_ID="scope-123"
  export CONTEXT='{"scope":{"nrn":"organization=1:account=2:namespace=3:application=4:scope=5"}}'
  unset ASSUME_ROLE_ARN ASSUME_ROLE_ARN_DEFAULT ASSUME_ROLE_SELECTOR

  # np mock: IAM provider with a k8s selector
  np() {
    case "$*" in
      *"provider list"*"aws-iam-configuration"*) echo '{"results":[{"id":"prov-iam-1"}]}' ;;
      *"provider read"*"prov-iam-1"*) echo '{"attributes":{"iam_role_arns":{"arns":[{"selector":"k8s","arn":"arn:aws:iam::111:role/k8s-role"}]}}}' ;;
      *) echo '{"results":[]}' ;;
    esac
  }
  export -f np

  # aws sts mock: success
  aws() {
    case "$*" in
      *"sts assume-role"*) echo '{"Credentials":{"AccessKeyId":"AKIA1","SecretAccessKey":"sec1","SessionToken":"tok1"}}' ;;
      *) return 0 ;;
    esac
  }
  export -f aws
}

@test "assume_role_step: resolves k8s role from the IAM provider and exports creds" {
  run bash -c "source '$STEP'; echo \"\$AWS_ACCESS_KEY_ID|\$ASSUME_ROLE_ARN\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "AKIA1|arn:aws:iam::111:role/k8s-role"
}

@test "assume_role_step: no role resolved is not an error (agent creds remain)" {
  np() { echo '{"results":[]}'; }
  export -f np
  run bash -c "source '$STEP'; echo \"ak=\${AWS_ACCESS_KEY_ID:-none} sk=\${AWS_SECRET_ACCESS_KEY:-none} st=\${AWS_SESSION_TOKEN:-none} arn=[\${ASSUME_ROLE_ARN}]\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "ak=none"
  assert_contains "$output" "sk=none"
  assert_contains "$output" "st=none"
  assert_contains "$output" "arn=[]"
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

@test "assume_role_step: honors ASSUME_ROLE_SELECTOR override" {
  export ASSUME_ROLE_SELECTOR="custom"
  np() {
    case "$*" in
      *"provider list"*"aws-iam-configuration"*) echo '{"results":[{"id":"prov-iam-1"}]}' ;;
      *"provider read"*"prov-iam-1"*) echo '{"attributes":{"iam_role_arns":{"arns":[{"selector":"custom","arn":"arn:aws:iam::111:role/custom-role"}]}}}' ;;
      *) echo '{"results":[]}' ;;
    esac
  }
  export -f np
  run bash -c "source '$STEP'; echo \"\$ASSUME_ROLE_ARN\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "arn:aws:iam::111:role/custom-role"
}

@test "assume_role_step: pre-set ASSUME_ROLE_ARN overrides provider resolution" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111:role/explicit-override"
  # np would resolve a different role, but the explicit override must win
  run bash -c "source '$STEP'; echo \"\$ASSUME_ROLE_ARN|\$AWS_ACCESS_KEY_ID\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "arn:aws:iam::111:role/explicit-override|AKIA1"
}

@test "assume_role_step: passes scope dimensions to the IAM provider lookup" {
  # Scope with dimensions; the dimension-matched config carries the role.
  export CONTEXT='{"scope":{"nrn":"organization=1:account=2:namespace=3:application=4:scope=5","dimensions":{"region":"us-east-1","environment":"production"}}}'
  np() {
    case "$*" in
      *"provider list"*"aws-iam-configuration"*"--dimensions region=us-east-1,environment=production"*)
        echo '{"results":[{"id":"prov-dim"}]}' ;;
      *"provider read"*"prov-dim"*)
        echo '{"attributes":{"iam_role_arns":{"arns":[{"selector":"k8s","arn":"arn:aws:iam::111:role/dim-role"}]}}}' ;;
      *) echo '{"results":[]}' ;;
    esac
  }
  export -f np
  run bash -c "source '$STEP'; echo \"\$ASSUME_ROLE_ARN\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "arn:aws:iam::111:role/dim-role"
}
