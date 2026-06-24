#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/utils/assume_role_lib — pure helpers.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$PARAMETERS_DIR/utils/assume_role_lib"
}

teardown() {
  unset SECRET_MANAGER_ASSUME_ROLE_ARN SECRET_MANAGER_ASSUME_ROLE_ARN_DEFAULT
}

# ---- arn_for_selector -------------------------------------------------------

@test "arn_for_selector: returns matching ARN when selector exists" {
  local json='{"iam_role_arns":{"arns":[
    {"selector":"containers","arn":"arn:aws:iam::1:role/containers"},
    {"selector":"secret_manager","arn":"arn:aws:iam::1:role/secret-mgr"}
  ]}}'

  run arn_for_selector "$json" "secret_manager"

  assert_equal "$status" "0"
  assert_equal "$output" "arn:aws:iam::1:role/secret-mgr"
}

@test "arn_for_selector: returns first match when selector appears twice" {
  local json='{"iam_role_arns":{"arns":[
    {"selector":"secret_manager","arn":"arn:1"},
    {"selector":"secret_manager","arn":"arn:2"}
  ]}}'

  run arn_for_selector "$json" "secret_manager"

  assert_equal "$output" "arn:1"
}

@test "arn_for_selector: returns empty string when selector not found" {
  local json='{"iam_role_arns":{"arns":[{"selector":"containers","arn":"a"}]}}'

  run arn_for_selector "$json" "secret_manager"

  assert_equal "$status" "0"
  assert_equal "$output" ""
}

@test "arn_for_selector: empty input returns empty (no crash)" {
  run arn_for_selector "" "secret_manager"
  assert_equal "$output" ""

  run arn_for_selector "{}" "secret_manager"
  assert_equal "$output" ""

  run arn_for_selector '{"iam_role_arns":{}}' "secret_manager"
  assert_equal "$output" ""
}

@test "arn_for_selector: malformed JSON returns empty (no crash)" {
  run arn_for_selector "not-json-at-all" "secret_manager"
  assert_equal "$output" ""
}

# ---- resolve_assume_role_arn -----------------------------------------------

@test "resolve_assume_role_arn: env var SECRET_MANAGER_ASSUME_ROLE_ARN wins" {
  export SECRET_MANAGER_ASSUME_ROLE_ARN="arn:aws:iam::1:role/from-env"
  local json='{"iam_role_arns":{"arns":[{"selector":"secret_manager","arn":"arn:provider"}]}}'

  run resolve_assume_role_arn "$json" "secret_manager"

  assert_equal "$output" "arn:aws:iam::1:role/from-env"
}

@test "resolve_assume_role_arn: empty env falls through to provider selector" {
  export SECRET_MANAGER_ASSUME_ROLE_ARN=""
  local json='{"iam_role_arns":{"arns":[{"selector":"secret_manager","arn":"arn:provider"}]}}'

  run resolve_assume_role_arn "$json" "secret_manager"

  assert_equal "$output" "arn:provider"
}

@test "resolve_assume_role_arn: provider miss falls through to DEFAULT env" {
  unset SECRET_MANAGER_ASSUME_ROLE_ARN
  export SECRET_MANAGER_ASSUME_ROLE_ARN_DEFAULT="arn:aws:iam::1:role/default"
  local json='{"iam_role_arns":{"arns":[{"selector":"containers","arn":"a"}]}}'

  run resolve_assume_role_arn "$json" "secret_manager"

  assert_equal "$output" "arn:aws:iam::1:role/default"
}

@test "resolve_assume_role_arn: no source set returns empty (agent creds)" {
  unset SECRET_MANAGER_ASSUME_ROLE_ARN SECRET_MANAGER_ASSUME_ROLE_ARN_DEFAULT

  run resolve_assume_role_arn "{}" "secret_manager"

  assert_equal "$output" ""
}
