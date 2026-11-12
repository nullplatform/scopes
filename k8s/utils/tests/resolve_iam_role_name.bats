#!/usr/bin/env bats
# =============================================================================
# Unit tests for resolve_iam_role_name - the IAM role (and service account) name
# of a scope: IAM.PREFIX followed by the scope id, where the prefix may be a
# pattern rendered by the resource naming engine
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  source "$BATS_TEST_DIRNAME/../resolve_iam_role_name"

  export KUBECTL_LOG="$(mktemp)"
  export MOCK_SERVICE_ACCOUNT=""

  kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    case "$*" in
      "get serviceaccounts -n "*" -l scope_id="*)
        printf '%s' "$MOCK_SERVICE_ACCOUNT" ;;
      *)
        return 0 ;;
    esac
  }
  export -f kubectl

  export MOCK_ROLE_SCOPE_ID="123456"
  aws() {
    echo "$*" >> "$KUBECTL_LOG"
    case "$*" in
      "iam get-role --role-name "*"scope_id"*) printf '%s\n' "$MOCK_ROLE_SCOPE_ID" ;;
      *) return 0 ;;
    esac
  }
  export -f aws

  export CONTEXT='{
    "scope": {"id": 123456, "slug": "production", "dimensions": {"environment": "production"}},
    "application": {"id": 42, "slug": "checkout-api"},
    "namespace": {"id": 300, "slug": "payments"},
    "account": {"id": 20, "slug": "acme"}
  }'
}

teardown() {
  rm -f "$KUBECTL_LOG"
  unset -f kubectl aws log
}

@test "resolve_iam_role_name: a plain prefix is followed by the scope id" {
  resolve_iam_role_name "nullplatform-scopes" "123456" "payments"

  assert_equal "$IAM_ROLE_NAME" "nullplatform-scopes-123456"
}

@test "resolve_iam_role_name: a plain prefix is kept verbatim, uppercase and underscores included" {
  resolve_iam_role_name "Acme_Scopes" "123456" "payments"

  assert_equal "$IAM_ROLE_NAME" "Acme_Scopes-123456"
}

@test "resolve_iam_role_name: a plain prefix never looks up the cluster" {
  export MOCK_SERVICE_ACCOUNT="something-else-123456"

  resolve_iam_role_name "nullplatform-scopes" "123456" "payments"

  assert_equal "$IAM_ROLE_NAME" "nullplatform-scopes-123456"
  assert_empty "$(cat "$KUBECTL_LOG")"
}

@test "resolve_iam_role_name: a pattern prefix is rendered from the context" {
  resolve_iam_role_name "{.account.slug}-{.namespace.slug}" "123456" "payments"

  assert_equal "$IAM_ROLE_NAME" "acme-payments-123456"
}

@test "resolve_iam_role_name: a pattern prefix accepts leading and trailing literals" {
  resolve_iam_role_name "np-{.application.slug}-{.scope.dimensions.environment}-role" "123456" "payments"

  assert_equal "$IAM_ROLE_NAME" "np-checkout-api-production-role-123456"
}

@test "resolve_iam_role_name: a scope that already has a service account keeps its name" {
  export MOCK_SERVICE_ACCOUNT="acme-old-namespace-123456"

  resolve_iam_role_name "{.account.slug}-{.namespace.slug}" "123456" "payments"

  assert_equal "$IAM_ROLE_NAME" "acme-old-namespace-123456"
  assert_contains "$(cat "$KUBECTL_LOG")" "get serviceaccounts -n payments -l scope_id=123456"
  assert_contains "$(cat "$KUBECTL_LOG")" "iam get-role --role-name acme-old-namespace-123456"
}

@test "resolve_iam_role_name: long slugs are trimmed so the name fits the 64-character IAM limit" {
  export CONTEXT='{
    "scope": {"id": 123456},
    "application": {"slug": "a-very-long-application-slug-that-goes-on-and-on"},
    "namespace": {"slug": "an-equally-long-namespace-slug-for-the-payments-team"}
  }'

  resolve_iam_role_name "{.namespace.slug}-{.application.slug}" "123456" "payments"

  [ "${#IAM_ROLE_NAME}" -le 64 ] || false
  [[ "$IAM_ROLE_NAME" == an-equally-long-* ]] || false
  [[ "$IAM_ROLE_NAME" == *-123456 ]]
}

@test "resolve_iam_role_name: a prefix that cannot be rendered fails with a hint" {
  run resolve_iam_role_name "{.account.slug | ascii}" "123456" "payments"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Naming pattern '{.account.slug | ascii}' has an unsafe path {.account.slug | ascii}"
  assert_contains "$output" "❌ Could not render the IAM role name from prefix '{.account.slug | ascii}'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Fix IAM.PREFIX; see k8s/docs/resource-naming.md"
}

@test "resolve_iam_role_name: a service account whose role is not tagged for the scope is not adopted" {
  export MOCK_SERVICE_ACCOUNT="someone-elses-role"
  export MOCK_ROLE_SCOPE_ID="999999"

  resolve_iam_role_name "{.account.slug}-{.namespace.slug}" "123456" "payments" 2>"$BATS_TEST_TMPDIR/stderr" > "$BATS_TEST_TMPDIR/stdout"

  assert_equal "$IAM_ROLE_NAME" "acme-payments-123456"
  assert_contains "$(cat "$BATS_TEST_TMPDIR/stdout")" "⚠️  Ignoring service account 'someone-elses-role': its IAM role is not tagged with scope_id=123456"
}

@test "resolve_iam_role_name: a failing service account lookup fails instead of renaming the role" {
  kubectl() { echo "Forbidden" >&2; return 1; }
  export -f kubectl

  run resolve_iam_role_name "{.account.slug}-{.namespace.slug}" "123456" "payments"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Could not look up the service account of scope 123456 in namespace 'payments'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check that the agent can list serviceaccounts in 'payments'"
}

@test "resolve_iam_role_name: a service account whose role cannot be read is not adopted" {
  export MOCK_SERVICE_ACCOUNT="acme-old-namespace-123456"
  aws() { echo "An error occurred (NoSuchEntity)" >&2; return 1; }
  export -f aws

  resolve_iam_role_name "{.account.slug}-{.namespace.slug}" "123456" "payments" > "$BATS_TEST_TMPDIR/stdout"

  assert_equal "$IAM_ROLE_NAME" "acme-payments-123456"
  assert_contains "$(cat "$BATS_TEST_TMPDIR/stdout")" "⚠️  Ignoring service account 'acme-old-namespace-123456': its IAM role is not tagged with scope_id=123456"
}

@test "resolve_iam_role_name: with several labelled service accounts the first one is checked" {
  export MOCK_SERVICE_ACCOUNT="acme-old-namespace-123456 another-123456"

  resolve_iam_role_name "{.account.slug}-{.namespace.slug}" "123456" "payments"

  assert_equal "$IAM_ROLE_NAME" "acme-old-namespace-123456"
}
