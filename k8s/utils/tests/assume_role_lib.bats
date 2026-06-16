#!/usr/bin/env bats
# =============================================================================
# Unit tests for utils/assume_role_lib - pure assume-role ARN resolution
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Library under test (pure functions, safe to source)
  source "$BATS_TEST_DIRNAME/../assume_role_lib"

  # Default np mock: an aws-iam-configuration provider with two selectors,
  # plus a scope-configurations provider carrying a legacy assume_role.arn.
  np() {
    case "$*" in
      *"provider list"*"aws-iam-configuration"*)
        echo '{"results":[{"id":"prov-iam-1"}]}' ;;
      *"provider read"*"prov-iam-1"*)
        echo '{"attributes":{"iam_role_arns":{"arns":[{"selector":"lambda","arn":"arn:aws:iam::111:role/lambda-role"},{"selector":"k8s","arn":"arn:aws:iam::111:role/k8s-role"}]}}}' ;;
      *"provider list"*"scope-configurations"*)
        echo '{"results":[{"attributes":{"assume_role":{"arn":"arn:aws:iam::111:role/scope-cfg-role"}}}]}' ;;
      *)
        echo '{"results":[]}' ;;
    esac
  }
  export -f np

  # Clear precedence env vars between tests
  unset ASSUME_ROLE_ARN ASSUME_ROLE_ARN_DEFAULT
}

teardown() {
  unset ASSUME_ROLE_ARN ASSUME_ROLE_ARN_DEFAULT
}

@test "arn_for_selector_from_json: returns the arn matching the selector" {
  json='{"attributes":{"iam_role_arns":{"arns":[{"selector":"lambda","arn":"arn:aws:iam::111:role/lambda-role"},{"selector":"k8s","arn":"arn:aws:iam::111:role/k8s-role"}]}}}'
  run arn_for_selector_from_json "$json" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/k8s-role"
}

@test "arn_for_selector_from_json: first match wins when selector is duplicated" {
  json='{"attributes":{"iam_role_arns":{"arns":[{"selector":"k8s","arn":"arn:aws:iam::111:role/first"},{"selector":"k8s","arn":"arn:aws:iam::111:role/second"}]}}}'
  run arn_for_selector_from_json "$json" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/first"
}

@test "arn_for_selector_from_json: empty when no selector matches" {
  json='{"attributes":{"iam_role_arns":{"arns":[{"selector":"lambda","arn":"arn:aws:iam::111:role/lambda-role"}]}}}'
  run arn_for_selector_from_json "$json" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "arn_for_selector_from_json: empty on malformed json (no crash)" {
  run arn_for_selector_from_json "not-json" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "resolve_assume_role_arn: ASSUME_ROLE_ARN env wins (override)" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111:role/override"
  run resolve_assume_role_arn "organization=1:account=2" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/override"
}

@test "resolve_assume_role_arn: resolves from IAM provider by selector k8s" {
  run resolve_assume_role_arn "organization=1:account=2" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/k8s-role"
}

@test "resolve_assume_role_arn: falls back to scope-configurations assume_role.arn" {
  # IAM provider returns no match for this selector -> scope-config fallback
  run resolve_assume_role_arn "organization=1:account=2" "does-not-exist"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/scope-cfg-role"
}

@test "resolve_assume_role_arn: falls back to ASSUME_ROLE_ARN_DEFAULT" {
  export ASSUME_ROLE_ARN_DEFAULT="arn:aws:iam::111:role/agent-default"
  # No IAM provider, no scope-config
  np() { echo '{"results":[]}'; }
  export -f np
  run resolve_assume_role_arn "organization=1:account=2" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/agent-default"
}

@test "resolve_assume_role_arn: empty when nothing is configured" {
  np() { echo '{"results":[]}'; }
  export -f np
  run resolve_assume_role_arn "organization=1:account=2" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "provider_arn_for_selector: resolves the arn for the matching selector via np" {
  run provider_arn_for_selector "organization=1:account=2" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/k8s-role"
}

@test "provider_arn_for_selector: empty when no IAM provider is found" {
  np() { echo '{"results":[]}'; }
  export -f np
  run provider_arn_for_selector "organization=1:account=2" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "scope_config_assume_role_arn: returns assume_role.arn from scope-configurations provider" {
  run scope_config_assume_role_arn "organization=1:account=2"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/scope-cfg-role"
}

@test "scope_config_assume_role_arn: empty when no scope-configurations provider" {
  np() { echo '{"results":[]}'; }
  export -f np
  run scope_config_assume_role_arn "organization=1:account=2"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}
