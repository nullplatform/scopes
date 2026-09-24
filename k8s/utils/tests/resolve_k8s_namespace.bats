#!/usr/bin/env bats
# =============================================================================
# Unit tests for resolve_k8s_namespace - maps a nullplatform namespace to a
# k8s namespace according to K8S_NAMESPACE_STRATEGY
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../resolve_k8s_namespace"

  export KUBECTL_CALLS="$BATS_TEST_TMPDIR/kubectl_calls"

  # Default cluster: empty (no scope resources, no namespaces)
  export MOCK_SCOPE_NAMESPACE=""
  export MOCK_PINNED_NAMESPACE=""
  export MOCK_EXISTING_NAMESPACE=""
  export MOCK_EXISTING_NAMESPACE_OWNER=""
  export MOCK_DISCOVERY_FORBIDDEN=""
  export MOCK_DNS_NAMESPACE=""
  export MOCK_NO_DNS_CRD=""

  kubectl() {
    echo "kubectl $*" >> "$KUBECTL_CALLS"
    case "$*" in
      "get deployment,serviceaccount,service -A -l scope_id="*)
        [ -n "$MOCK_DISCOVERY_FORBIDDEN" ] && { echo "Error from server (Forbidden)" >&2; return 1; }
        echo -n "$MOCK_SCOPE_NAMESPACE"
        ;;
      "get dnsendpoints.externaldns.k8s.io -A -l scope_id="*)
        [ -n "$MOCK_NO_DNS_CRD" ] && { echo "error: the server doesn't have a resource type \"dnsendpoints\"" >&2; return 1; }
        echo -n "$MOCK_DNS_NAMESPACE"
        ;;
      "get namespace -l nullplatform=true,namespace_id="*)
        echo -n "$MOCK_PINNED_NAMESPACE"
        ;;
      "get namespace $MOCK_EXISTING_NAMESPACE -o jsonpath={.metadata.labels.namespace_id}")
        [ -z "$MOCK_EXISTING_NAMESPACE" ] && return 1
        echo -n "$MOCK_EXISTING_NAMESPACE_OWNER"
        ;;
      "get namespace "*)
        return 1
        ;;
    esac
  }
  export -f kubectl

  export CONTEXT='{
    "scope": {
      "id": "7",
      "nrn": "nrn:organization=100:account=200:namespace=300:application=400:scope=7"
    },
    "account": {"id": 200, "slug": "acme"},
    "namespace": {"id": 300, "slug": "payments"},
    "providers": {}
  }'
}

teardown() {
  unset K8S_NAMESPACE_STRATEGY K8S_NAMESPACE NAMESPACE_OVERRIDE K8S_RESERVED_NAMESPACES
}

with_strategy_provider() {
  export CONTEXT=$(echo "$CONTEXT" | jq --arg s "$1" '.providers["scope-configurations"].cluster.namespace_strategy = $s')
}

# =============================================================================
# sanitize_k8s_namespace_name
# =============================================================================
@test "sanitize_k8s_namespace_name: lowercases and replaces invalid characters" {
  assert_equal "$(sanitize_k8s_namespace_name "Payments_Team.v2")" "payments-team-v2"
}

@test "sanitize_k8s_namespace_name: trims leading and trailing dashes" {
  assert_equal "$(sanitize_k8s_namespace_name "--payments--")" "payments"
}

@test "sanitize_k8s_namespace_name: truncates long names to 63 chars with a stable hash suffix" {
  local long="acme-$(printf 'x%.0s' {1..80})"

  local first second
  first=$(sanitize_k8s_namespace_name "$long")
  second=$(sanitize_k8s_namespace_name "$long")

  assert_equal "${#first}" "63"
  assert_equal "$first" "$second"
  [[ "$first" =~ ^acme-x+-[0-9a-f]{6}$ ]]
}

# =============================================================================
# static strategy (default) - current behaviour
# =============================================================================
@test "resolve_k8s_namespace: defaults to static strategy and returns nullplatform" {
  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "nullplatform"
}

@test "resolve_k8s_namespace: static strategy never queries the cluster" {
  export K8S_NAMESPACE_STRATEGY="static"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_file_not_exists "$KUBECTL_CALLS"
}

@test "resolve_k8s_namespace: static strategy honours the existing namespace precedence" {
  export K8S_NAMESPACE="env-namespace"
  export CONTEXT=$(echo "$CONTEXT" | jq '
    .providers["scope-configurations"].cluster.namespace = "scope-config-namespace" |
    .providers["container-orchestration"].cluster.namespace = "container-orch-namespace"')

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "scope-config-namespace"
}

# =============================================================================
# np_namespace strategy
# =============================================================================
@test "resolve_k8s_namespace: np_namespace uses the nullplatform namespace slug for a new namespace" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "payments"
}

@test "resolve_k8s_namespace: strategy can be set from the scope-configurations provider" {
  with_strategy_provider "np_namespace"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "payments"
}

@test "resolve_k8s_namespace: an existing scope stays where its resources already live" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export MOCK_SCOPE_NAMESPACE="nullplatform"
  export MOCK_PINNED_NAMESPACE="payments"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "nullplatform"
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get deployment,serviceaccount,service -A -l scope_id=7"
}

@test "resolve_k8s_namespace: a renamed nullplatform namespace keeps its pinned k8s namespace" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export CONTEXT=$(echo "$CONTEXT" | jq '.namespace.slug = "payments-renamed"')
  export MOCK_PINNED_NAMESPACE="payments"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "payments"
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get namespace -l nullplatform=true,namespace_id=300"
}

@test "resolve_k8s_namespace: takes the namespace id from the scope nrn when namespace.id is missing" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.namespace.id)')
  export MOCK_PINNED_NAMESPACE="payments"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get namespace -l nullplatform=true,namespace_id=300"
}

@test "resolve_k8s_namespace: falls through when scope discovery is forbidden" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export MOCK_DISCOVERY_FORBIDDEN="true"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "payments"
}

@test "resolve_k8s_namespace: reuses an existing namespace owned by the same nullplatform namespace" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export MOCK_EXISTING_NAMESPACE="payments"
  export MOCK_EXISTING_NAMESPACE_OWNER="300"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "payments"
}

# =============================================================================
# np_account_namespace strategy
# =============================================================================
@test "resolve_k8s_namespace: np_account_namespace prefixes the account slug" {
  export K8S_NAMESPACE_STRATEGY="np_account_namespace"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "acme-payments"
}

# =============================================================================
# Error scenarios
# =============================================================================
@test "resolve_k8s_namespace: fails on unknown strategy" {
  export K8S_NAMESPACE_STRATEGY="by_team"

  run resolve_k8s_namespace

  [ "$status" -eq 1 ]
  assert_equal "$output" "❌ Unknown K8S_NAMESPACE_STRATEGY 'by_team' (valid: static, np_namespace, np_account_namespace)"
}

@test "resolve_k8s_namespace: rejects reserved namespace names" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export CONTEXT=$(echo "$CONTEXT" | jq '.namespace.slug = "kube-system"')

  run resolve_k8s_namespace

  [ "$status" -eq 1 ]
  assert_equal "$output" "❌ Namespace 'kube-system' is reserved and cannot host applications"
}

@test "resolve_k8s_namespace: the static namespace is reserved in dynamic strategies" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export CONTEXT=$(echo "$CONTEXT" | jq '.namespace.slug = "shared-infra"')
  export K8S_NAMESPACE="shared-infra"

  run resolve_k8s_namespace

  [ "$status" -eq 1 ]
  assert_equal "$output" "❌ Namespace 'shared-infra' is reserved and cannot host applications"
}

@test "resolve_k8s_namespace: reserved list can be overridden" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export K8S_RESERVED_NAMESPACES="payments"

  run resolve_k8s_namespace

  [ "$status" -eq 1 ]
  assert_equal "$output" "❌ Namespace 'payments' is reserved and cannot host applications"
}

@test "resolve_k8s_namespace: fails when the namespace belongs to another nullplatform namespace" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export MOCK_EXISTING_NAMESPACE="payments"
  export MOCK_EXISTING_NAMESPACE_OWNER="999"

  run resolve_k8s_namespace

  [ "$status" -eq 1 ]
  assert_equal "$output" "❌ Namespace 'payments' already belongs to nullplatform namespace_id=999 (expected 300). Use K8S_NAMESPACE_STRATEGY=np_account_namespace to avoid collisions across accounts"
}

@test "resolve_k8s_namespace: refuses to adopt a namespace not managed by nullplatform" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export MOCK_EXISTING_NAMESPACE="payments"
  export MOCK_EXISTING_NAMESPACE_OWNER=""

  run resolve_k8s_namespace

  [ "$status" -eq 1 ]
  assert_equal "$output" "❌ Namespace 'payments' already exists and is not managed by nullplatform; refusing to adopt it"
}

# =============================================================================
# find_scope_namespace (used by read-only actions)
# =============================================================================
@test "find_scope_namespace: returns the namespace where the scope resources live" {
  export MOCK_SCOPE_NAMESPACE="payments"

  run find_scope_namespace "7"

  [ "$status" -eq 0 ]
  assert_equal "$output" "payments"
}

@test "find_scope_namespace: returns empty when the scope has no resources" {
  run find_scope_namespace "7"

  [ "$status" -eq 0 ]
  assert_empty "$output"
}

@test "resolve_k8s_namespace: accepts an explicit scope id when CONTEXT has none" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.scope.id)')
  export MOCK_SCOPE_NAMESPACE="payments"

  run resolve_k8s_namespace "42"

  [ "$status" -eq 0 ]
  assert_equal "$output" "payments"
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get deployment,serviceaccount,service -A -l scope_id=42"
}

@test "resolve_k8s_namespace: fails when the nullplatform namespace slug is missing" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.namespace.slug)')

  run resolve_k8s_namespace

  [ "$status" -eq 1 ]
  assert_equal "$output" "❌ Cannot compute the k8s namespace: nullplatform namespace slug not found in context"
}

# =============================================================================
# find_application_namespace (used by log when there is no scope_id)
# =============================================================================
@test "find_application_namespace: returns the namespace of the application pods" {
  kubectl() {
    case "$*" in
      "get pods -A -l nullplatform=true,application_id=400"*) echo -n "payments payments" ;;
    esac
  }
  export -f kubectl

  run find_application_namespace "400"

  [ "$status" -eq 0 ]
  assert_equal "$output" "payments"
}

@test "find_scope_namespace: finds a scope whose only remaining resource is its DNSEndpoint" {
  export MOCK_DNS_NAMESPACE="nullplatform"

  run find_scope_namespace "7"

  [ "$status" -eq 0 ]
  assert_equal "$output" "nullplatform"
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get dnsendpoints.externaldns.k8s.io -A -l scope_id=7"
}

@test "find_scope_namespace: tolerates a cluster without the DNSEndpoint CRD" {
  export MOCK_NO_DNS_CRD="true"

  run find_scope_namespace "7"

  [ "$status" -eq 0 ]
  assert_empty "$output"
}

@test "resolve_k8s_namespace: a legacy scope keeps its namespace in delete-scope after delete-deployment" {
  export K8S_NAMESPACE_STRATEGY="np_namespace"
  export MOCK_DNS_NAMESPACE="nullplatform"

  run resolve_k8s_namespace

  [ "$status" -eq 0 ]
  assert_equal "$output" "nullplatform"
}
