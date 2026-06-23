#!/usr/bin/env bats
# =============================================================================
# Unit tests for utils/assume_role_lib - pure assume-role ARN resolution.
#
# The library reads the AWS IAM provider as it appears in
# CONTEXT.providers["identity-access-control"] — already resolved for the scope's
# dimensions by the platform. The functions are pure JSON processors (jq only),
# so no np/aws mocking is needed.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../assume_role_lib"
  unset CONTAINERS_ASSUME_ROLE_ARN CONTAINERS_ASSUME_ROLE_ARN_DEFAULT
}

teardown() {
  unset CONTAINERS_ASSUME_ROLE_ARN CONTAINERS_ASSUME_ROLE_ARN_DEFAULT
}

# --- arn_for_selector ---------------------------------------------------------

@test "arn_for_selector: returns the arn matching the selector" {
  json='{"iam_role_arns":{"arns":[{"selector":"lambda","arn":"arn:aws:iam::111:role/lambda-role"},{"selector":"containers","arn":"arn:aws:iam::111:role/containers-role"}]}}'
  run arn_for_selector "$json" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/containers-role"
}

@test "arn_for_selector: first match wins when selector is duplicated" {
  json='{"iam_role_arns":{"arns":[{"selector":"containers","arn":"arn:aws:iam::111:role/first"},{"selector":"containers","arn":"arn:aws:iam::111:role/second"}]}}'
  run arn_for_selector "$json" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/first"
}

@test "arn_for_selector: empty when no selector matches" {
  json='{"iam_role_arns":{"arns":[{"selector":"lambda","arn":"arn:aws:iam::111:role/lambda-role"}]}}'
  run arn_for_selector "$json" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "arn_for_selector: empty on empty/malformed json (no crash)" {
  run arn_for_selector "{}" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
  run arn_for_selector "not-json" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

# --- resolve_assume_role_arn (precedence) ------------------------------------

@test "resolve_assume_role_arn: CONTAINERS_ASSUME_ROLE_ARN env wins (override)" {
  export CONTAINERS_ASSUME_ROLE_ARN="arn:aws:iam::111:role/override"
  run resolve_assume_role_arn '{"iam_role_arns":{"arns":[{"selector":"containers","arn":"arn:aws:iam::111:role/containers-role"}]}}' "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/override"
}

@test "resolve_assume_role_arn: resolves from the IAM provider by selector" {
  run resolve_assume_role_arn '{"iam_role_arns":{"arns":[{"selector":"containers","arn":"arn:aws:iam::111:role/containers-role"}]}}' "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/containers-role"
}

@test "resolve_assume_role_arn: falls back to CONTAINERS_ASSUME_ROLE_ARN_DEFAULT" {
  export CONTAINERS_ASSUME_ROLE_ARN_DEFAULT="arn:aws:iam::111:role/agent-default"
  run resolve_assume_role_arn '{}' "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "arn:aws:iam::111:role/agent-default"
}

@test "resolve_assume_role_arn: empty when nothing is configured" {
  run resolve_assume_role_arn '{}' "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}
