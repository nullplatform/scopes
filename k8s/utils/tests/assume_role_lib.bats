#!/usr/bin/env bats
# =============================================================================
# Unit tests for utils/assume_role_lib - pure assume-role ARN resolution.
#
# The library reads the AWS IAM provider and scope-configurations provider as
# they appear in CONTEXT.providers[...] — already resolved for the scope's
# dimensions by the platform. The functions are pure JSON processors (jq only),
# so no np/aws mocking is needed.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../assume_role_lib"
  unset ASSUME_ROLE_ARN ASSUME_ROLE_ARN_DEFAULT
}

teardown() {
  unset ASSUME_ROLE_ARN ASSUME_ROLE_ARN_DEFAULT
}

# --- arn_for_selector ---------------------------------------------------------

@test "arn_for_selector: returns the arn matching the selector" {
  json='{"iam_role_arns":{"arns":[{"selector":"lambda","arn":"arn:aws:iam::111:role/lambda-role"},{"selector":"k8s","arn":"arn:aws:iam::111:role/k8s-role"}]}}'
  run arn_for_selector "$json" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/k8s-role"
}

@test "arn_for_selector: first match wins when selector is duplicated" {
  json='{"iam_role_arns":{"arns":[{"selector":"k8s","arn":"arn:aws:iam::111:role/first"},{"selector":"k8s","arn":"arn:aws:iam::111:role/second"}]}}'
  run arn_for_selector "$json" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/first"
}

@test "arn_for_selector: empty when no selector matches" {
  json='{"iam_role_arns":{"arns":[{"selector":"lambda","arn":"arn:aws:iam::111:role/lambda-role"}]}}'
  run arn_for_selector "$json" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "arn_for_selector: empty on empty/malformed json (no crash)" {
  run arn_for_selector "{}" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
  run arn_for_selector "not-json" "k8s"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

# --- scope_config_assume_role_arn --------------------------------------------

@test "scope_config_assume_role_arn: returns assume_role.arn" {
  run scope_config_assume_role_arn '{"assume_role":{"arn":"arn:aws:iam::111:role/scope-cfg-role"}}'
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/scope-cfg-role"
}

@test "scope_config_assume_role_arn: empty when absent" {
  run scope_config_assume_role_arn '{"networking":{}}'
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

# --- resolve_assume_role_arn (precedence) ------------------------------------

@test "resolve_assume_role_arn: ASSUME_ROLE_ARN env wins (override)" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111:role/override"
  run resolve_assume_role_arn '{"iam_role_arns":{"arns":[{"selector":"k8s","arn":"arn:aws:iam::111:role/k8s-role"}]}}' "k8s" '{}'
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/override"
}

@test "resolve_assume_role_arn: resolves from the IAM provider by selector" {
  run resolve_assume_role_arn '{"iam_role_arns":{"arns":[{"selector":"k8s","arn":"arn:aws:iam::111:role/k8s-role"}]}}' "k8s" '{}'
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/k8s-role"
}

@test "resolve_assume_role_arn: falls back to scope-configurations assume_role.arn" {
  run resolve_assume_role_arn '{"iam_role_arns":{"arns":[]}}' "k8s" '{"assume_role":{"arn":"arn:aws:iam::111:role/scope-cfg-role"}}'
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/scope-cfg-role"
}

@test "resolve_assume_role_arn: falls back to ASSUME_ROLE_ARN_DEFAULT" {
  export ASSUME_ROLE_ARN_DEFAULT="arn:aws:iam::111:role/agent-default"
  run resolve_assume_role_arn '{}' "k8s" '{}'
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/agent-default"
}

@test "resolve_assume_role_arn: empty when nothing is configured" {
  run resolve_assume_role_arn '{}' "k8s" '{}'
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}
