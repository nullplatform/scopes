#!/usr/bin/env bats
# =============================================================================
# Unit tests for utils/assume_role - performs sts:AssumeRole, exports AWS_*
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export HELPER="$BATS_TEST_DIRNAME/../assume_role"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCOPE_ID="scope-123"
  unset ASSUME_ROLE_ARN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

  # Mock aws sts assume-role - success by default
  aws() {
    case "$*" in
      *"sts assume-role"*)
        echo '{"Credentials":{"AccessKeyId":"AKIAEXAMPLE","SecretAccessKey":"secret123","SessionToken":"token123"}}' ;;
      *) return 0 ;;
    esac
  }
  export -f aws
}

@test "assume_role: no-op when ASSUME_ROLE_ARN is empty (uses agent creds)" {
  run bash -c "source '$HELPER'; echo \"key=\${AWS_ACCESS_KEY_ID:-none}\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "key=none"
}

@test "assume_role: exports AWS_* credentials when ARN is set" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111:role/k8s-role"
  run bash -c "source '$HELPER'; echo \"\$AWS_ACCESS_KEY_ID|\$AWS_SECRET_ACCESS_KEY|\$AWS_SESSION_TOKEN\""
  [ "$status" -eq 0 ]
  assert_contains "$output" "AKIAEXAMPLE|secret123|token123"
}

@test "assume_role: returns non-zero when sts:AssumeRole fails" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111:role/k8s-role"
  aws() {
    case "$*" in
      *"sts assume-role"*) echo "AccessDenied" >&2; return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f aws
  run bash -c "source '$HELPER'"
  [ "$status" -ne 0 ]
}
