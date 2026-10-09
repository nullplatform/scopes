#!/usr/bin/env bats
# =============================================================================
# Unit tests for utils/azure_identity_lib - Azure managed identity resolution.
#
# The library reads the Azure identity provider as it appears in
# CONTEXT.providers["identity-access-control"] — already resolved for the
# scope's dimensions by the platform. The functions are JSON/env processors
# (jq only) plus reads of the projected token file, so no az/curl mocking is
# needed.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../azure_identity_lib"
  unset CONTAINERS_AZURE_CLIENT_ID CONTAINERS_AZURE_CLIENT_ID_DEFAULT \
        AZURE_FEDERATED_TOKEN_FILE AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_GRANT_ARGS

  PROVIDER='{"managed_identities":{"identities":[{"selector":"lambda","client_id":"aaaaaaaa-0000-0000-0000-000000000000"},{"selector":"containers","client_id":"11111111-1111-1111-1111-111111111111"}]}}'

  # Projected ServiceAccount token: header.payload.signature, payload base64url.
  TOKEN_PAYLOAD=$(printf '%s' '{"iss":"https://oidc.example.com/abc/","sub":"system:serviceaccount:nullplatform:nullplatform-agent"}' \
    | base64 | tr -d '\n=' | tr '+/' '-_')
  TOKEN_FILE="$(mktemp)"
  printf 'eyJhbGciOiJSUzI1NiJ9.%s.signature' "$TOKEN_PAYLOAD" > "$TOKEN_FILE"
}

teardown() {
  unset CONTAINERS_AZURE_CLIENT_ID CONTAINERS_AZURE_CLIENT_ID_DEFAULT \
        AZURE_FEDERATED_TOKEN_FILE AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_GRANT_ARGS
  rm -f "$TOKEN_FILE"
}

# --- client_id_for_selector ---------------------------------------------------

@test "client_id_for_selector: returns the client_id matching the selector" {
  run client_id_for_selector "$PROVIDER" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "11111111-1111-1111-1111-111111111111"
}

@test "client_id_for_selector: first match wins when selector is duplicated" {
  json='{"managed_identities":{"identities":[{"selector":"containers","client_id":"first"},{"selector":"containers","client_id":"second"}]}}'
  run client_id_for_selector "$json" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "first"
}

@test "client_id_for_selector: empty when no selector matches" {
  run client_id_for_selector "$PROVIDER" "scheduled-task"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "client_id_for_selector: empty on empty/malformed json and on an AWS provider (no crash)" {
  run client_id_for_selector "{}" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
  run client_id_for_selector "not-json" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
  run client_id_for_selector '{"iam_role_arns":{"arns":[{"selector":"containers","arn":"arn:aws:iam::111:role/r"}]}}' "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

# --- resolve_azure_client_id (precedence) -------------------------------------

@test "resolve_azure_client_id: CONTAINERS_AZURE_CLIENT_ID env wins (override)" {
  export CONTAINERS_AZURE_CLIENT_ID="override-id"
  run resolve_azure_client_id "$PROVIDER" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "override-id"
}

@test "resolve_azure_client_id: resolves from the provider by selector" {
  run resolve_azure_client_id "$PROVIDER" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "11111111-1111-1111-1111-111111111111"
}

@test "resolve_azure_client_id: explicitly empty override falls through to the provider" {
  export CONTAINERS_AZURE_CLIENT_ID=""
  run resolve_azure_client_id "$PROVIDER" "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "11111111-1111-1111-1111-111111111111"
}

@test "resolve_azure_client_id: falls back to CONTAINERS_AZURE_CLIENT_ID_DEFAULT" {
  export CONTAINERS_AZURE_CLIENT_ID_DEFAULT="agent-default-id"
  run resolve_azure_client_id '{}' "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" "agent-default-id"
}

@test "resolve_azure_client_id: empty when nothing is configured" {
  run resolve_azure_client_id '{}' "containers"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

# --- azure_uses_federated_token -----------------------------------------------

@test "azure_uses_federated_token: true with token file, client id and no secret" {
  export AZURE_FEDERATED_TOKEN_FILE="$TOKEN_FILE" AZURE_CLIENT_ID="cid" AZURE_CLIENT_SECRET=""
  run azure_uses_federated_token
  [ "$status" -eq 0 ]
}

@test "azure_uses_federated_token: false when a client secret is also set" {
  export AZURE_FEDERATED_TOKEN_FILE="$TOKEN_FILE" AZURE_CLIENT_ID="cid" AZURE_CLIENT_SECRET="secret"
  run azure_uses_federated_token
  [ "$status" -ne 0 ]
}

@test "azure_uses_federated_token: false when the token file is missing" {
  export AZURE_FEDERATED_TOKEN_FILE="/nonexistent/token" AZURE_CLIENT_ID="cid" AZURE_CLIENT_SECRET=""
  run azure_uses_federated_token
  [ "$status" -ne 0 ]
}

@test "azure_uses_federated_token: false without a client id" {
  export AZURE_FEDERATED_TOKEN_FILE="$TOKEN_FILE" AZURE_CLIENT_SECRET=""
  run azure_uses_federated_token
  [ "$status" -ne 0 ]
}

# --- azure_grant_args ---------------------------------------------------------

@test "azure_grant_args: client assertion under workload identity" {
  export AZURE_FEDERATED_TOKEN_FILE="$TOKEN_FILE" AZURE_CLIENT_ID="cid" AZURE_CLIENT_SECRET=""
  azure_grant_args
  assert_equal "${#AZURE_GRANT_ARGS[@]}" "4"
  assert_equal "${AZURE_GRANT_ARGS[0]}" "-d"
  assert_equal "${AZURE_GRANT_ARGS[1]}" "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  assert_equal "${AZURE_GRANT_ARGS[2]}" "--data-urlencode"
  assert_equal "${AZURE_GRANT_ARGS[3]}" "client_assertion@$TOKEN_FILE"
}

@test "azure_grant_args: client secret otherwise" {
  export AZURE_CLIENT_ID="cid" AZURE_CLIENT_SECRET="secret-123"
  azure_grant_args
  assert_equal "${#AZURE_GRANT_ARGS[@]}" "2"
  assert_equal "${AZURE_GRANT_ARGS[0]}" "-d"
  assert_equal "${AZURE_GRANT_ARGS[1]}" "client_secret=secret-123"
}

# --- azure_token_claim --------------------------------------------------------

@test "azure_token_claim: reads iss and sub from the projected token" {
  run azure_token_claim "$TOKEN_FILE" "iss"
  [ "$status" -eq 0 ]
  assert_equal "$output" "https://oidc.example.com/abc/"
  run azure_token_claim "$TOKEN_FILE" "sub"
  [ "$status" -eq 0 ]
  assert_equal "$output" "system:serviceaccount:nullplatform:nullplatform-agent"
}

@test "azure_token_claim: empty for a missing claim or an unreadable file (no crash)" {
  run azure_token_claim "$TOKEN_FILE" "aud"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
  run azure_token_claim "/nonexistent/token" "sub"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}
