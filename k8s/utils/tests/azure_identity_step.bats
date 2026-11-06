#!/usr/bin/env bats
# =============================================================================
# Unit tests for utils/azure_identity_step - picks the Azure managed identity
# (AKS workload identity) and verifies the federation with one token exchange.
#
# The identity provider is read from CONTEXT.providers["identity-access-control"]
# (already dimension-resolved by the platform), so the tests only mock `curl`.
# Success paths source the step IN-PROCESS and assert exported env vars
# directly; failure paths use `run` and assert the full hint output.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export STEP="$BATS_TEST_DIRNAME/../azure_identity_step"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export K8S_FLAVOR="aks"
  export AZURE_TENANT_ID="tenant-123"
  # Legacy Service Principal credentials the agent module still injects.
  export AZURE_CLIENT_ID="legacy-sp-client"
  export AZURE_CLIENT_SECRET="legacy-secret"
  export CONTEXT='{"providers":{"identity-access-control":{"managed_identities":{"identities":[{"selector":"containers","client_id":"11111111-1111-1111-1111-111111111111"}]}}}}'
  unset CONTAINERS_AZURE_CLIENT_ID CONTAINERS_AZURE_CLIENT_ID_DEFAULT CONTAINERS_AZURE_IDENTITY_SELECTOR

  # Projected ServiceAccount token, as the workload identity webhook mounts it.
  TOKEN_PAYLOAD=$(printf '%s' '{"iss":"https://oidc.example.com/abc/","sub":"system:serviceaccount:nullplatform:nullplatform-agent"}' \
    | base64 | tr -d '\n=' | tr '+/' '-_')
  export TOKEN_FILE="$(mktemp)"
  printf 'eyJhbGciOiJSUzI1NiJ9.%s.signature' "$TOKEN_PAYLOAD" > "$TOKEN_FILE"
  export AZURE_FEDERATED_TOKEN_FILE="$TOKEN_FILE"

  # curl mock: records its arguments, token exchange succeeds by default.
  export CURL_LOG="$(mktemp)"
  curl() {
    echo "$*" >> "$CURL_LOG"
    echo '{"access_token":"mock-token","token_type":"Bearer"}'
    echo "__HTTP_CODE__:200"
  }
  export -f curl
}

teardown() {
  unset CONTAINERS_AZURE_CLIENT_ID CONTAINERS_AZURE_CLIENT_ID_DEFAULT CONTAINERS_AZURE_IDENTITY_SELECTOR \
        AZURE_FEDERATED_TOKEN_FILE AZURE_CLIENT_ID AZURE_CLIENT_SECRET K8S_FLAVOR
  rm -f "$TOKEN_FILE" "$CURL_LOG"
}

@test "azure_identity_step: skipped outside AKS, legacy credentials untouched" {
  export K8S_FLAVOR="eks"
  logf=$(mktemp)
  source "$STEP" >"$logf" 2>&1
  [ "$AZURE_CLIENT_ID" = "legacy-sp-client" ]
  [ "$AZURE_CLIENT_SECRET" = "legacy-secret" ]
  [ ! -s "$CURL_LOG" ]
  assert_contains "$(cat "$logf")" "   ✅ azure_identity=skipped (K8S_FLAVOR=eks)"
}

@test "azure_identity_step: no identity configured is not an error (agent credentials remain)" {
  export CONTEXT='{"providers":{}}'
  logf=$(mktemp)
  source "$STEP" >"$logf" 2>&1
  [ "$AZURE_CLIENT_ID" = "legacy-sp-client" ]
  [ "$AZURE_CLIENT_SECRET" = "legacy-secret" ]
  [ ! -s "$CURL_LOG" ]
  assert_contains "$(cat "$logf")" "   ✅ azure_identity=skipped (using agent credentials)"
}

@test "azure_identity_step: resolves the containers identity, verifies it and exports it" {
  logf=$(mktemp)
  source "$STEP" >"$logf" 2>&1
  [ "$AZURE_CLIENT_ID" = "11111111-1111-1111-1111-111111111111" ]
  [ -z "$AZURE_CLIENT_SECRET" ]
  [ -z "${AZURE_PROBE_RESPONSE:-}" ]
  assert_contains "$(cat "$logf")" "   🔑 Using Azure managed identity: 11111111-1111-1111-1111-111111111111 (from provider selector 'containers')"
  assert_contains "$(cat "$logf")" "   ✅ Managed identity token exchange succeeded"

  sent=$(cat "$CURL_LOG")
  assert_contains "$sent" "https://login.microsoftonline.com/tenant-123/oauth2/v2.0/token"
  assert_contains "$sent" "--connect-timeout 10 --max-time 30"
  assert_contains "$sent" "client_id=11111111-1111-1111-1111-111111111111"
  assert_contains "$sent" "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  assert_contains "$sent" "client_assertion@$TOKEN_FILE"
  [[ "$sent" != *"client_secret="* ]]
}

@test "azure_identity_step: pre-set CONTAINERS_AZURE_CLIENT_ID overrides provider resolution" {
  export CONTAINERS_AZURE_CLIENT_ID="22222222-2222-2222-2222-222222222222"
  logf=$(mktemp)
  source "$STEP" >"$logf" 2>&1
  [ "$AZURE_CLIENT_ID" = "22222222-2222-2222-2222-222222222222" ]
  assert_contains "$(cat "$logf")" " (from env CONTAINERS_AZURE_CLIENT_ID)"
}

@test "azure_identity_step: honors CONTAINERS_AZURE_IDENTITY_SELECTOR override" {
  export CONTAINERS_AZURE_IDENTITY_SELECTOR="custom"
  export CONTEXT='{"providers":{"identity-access-control":{"managed_identities":{"identities":[{"selector":"custom","client_id":"33333333-3333-3333-3333-333333333333"}]}}}}'
  logf=$(mktemp)
  source "$STEP" >"$logf" 2>&1
  [ "$AZURE_CLIENT_ID" = "33333333-3333-3333-3333-333333333333" ]
}

@test "azure_identity_step: fails with hints when there is no projected token" {
  unset AZURE_FEDERATED_TOKEN_FILE
  run bash -c "source '$STEP'"
  [ "$status" -ne 0 ]
  assert_contains "$output" "   ❌ azure_identity step failed: no workload identity token to authenticate as 11111111-1111-1111-1111-111111111111"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   • The pod is missing the azure.workload.identity/use=\"true\" label"
  assert_contains "$output" "   • Workload identity is not enabled on the AKS cluster"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   • Set azure_workload_identity = true on the nullplatform agent module and re-apply it"
}

@test "azure_identity_step: AADSTS70021 prints the issuer and subject to federate" {
  curl() {
    echo '{"error":"invalid_request","error_description":"AADSTS70021: No matching federated identity record found for presented assertion."}'
    echo "__HTTP_CODE__:400"
  }
  export -f curl
  run bash -c "source '$STEP'"
  [ "$status" -ne 0 ]
  assert_contains "$output" "   ❌ azure_identity step failed: token exchange for 11111111-1111-1111-1111-111111111111 returned HTTP 400"
  assert_contains "$output" "   • The managed identity has no federated credential matching this pod's ServiceAccount token (AADSTS70021x)"
  assert_contains "$output" "   • Add a federated credential to identity 11111111-1111-1111-1111-111111111111 with issuer https://oidc.example.com/abc/, subject system:serviceaccount:nullplatform:nullplatform-agent and audience api://AzureADTokenExchange"
}

@test "azure_identity_step: AADSTS70021x (mismatch variant) prints the same hint" {
  curl() {
    echo '{"error":"invalid_request","error_description":"AADSTS700211: Unable to match the audience of the presented assertion."}'
    echo "__HTTP_CODE__:400"
  }
  export -f curl
  run bash -c "source '$STEP'"
  [ "$status" -ne 0 ]
  assert_contains "$output" "   • The managed identity has no federated credential matching this pod's ServiceAccount token (AADSTS70021x)"
  assert_contains "$output" "   • Add a federated credential to identity 11111111-1111-1111-1111-111111111111 with issuer https://oidc.example.com/abc/, subject system:serviceaccount:nullplatform:nullplatform-agent and audience api://AzureADTokenExchange"
}

@test "azure_identity_step: AADSTS700016 points at the provider client_id" {
  curl() {
    echo '{"error":"unauthorized_client","error_description":"AADSTS700016: Application with identifier was not found in the directory."}'
    echo "__HTTP_CODE__:400"
  }
  export -f curl
  run bash -c "source '$STEP'"
  [ "$status" -ne 0 ]
  assert_contains "$output" "   • No managed identity with client ID 11111111-1111-1111-1111-111111111111 exists in tenant tenant-123 (AADSTS700016)"
  assert_contains "$output" "   • Check the client ID set in the Azure Identity & Access provider (Platform Settings), selector 'containers'"
}

@test "azure_identity_step: other token errors print Azure AD's description" {
  curl() {
    echo '{"error":"invalid_client","error_description":"AADSTS7000215: Invalid client secret provided."}'
    echo "__HTTP_CODE__:401"
  }
  export -f curl
  run bash -c "source '$STEP'"
  [ "$status" -ne 0 ]
  assert_contains "$output" "returned HTTP 401"
  assert_contains "$output" "   • Azure AD rejected the token request: AADSTS7000215: Invalid client secret provided."
}

@test "azure_identity_step: fails with hints when the token endpoint is unreachable" {
  curl() { echo "Could not resolve host: login.microsoftonline.com" >&2; return 6; }
  export -f curl
  run bash -c "source '$STEP'"
  [ "$status" -ne 0 ]
  assert_contains "$output" "   ❌ azure_identity step failed: could not reach the Azure token endpoint"
  assert_contains "$output" "   • Network egress to login.microsoftonline.com is blocked"
  assert_contains "$output" "   • Allow HTTPS egress from the agent namespace to login.microsoftonline.com"
}
