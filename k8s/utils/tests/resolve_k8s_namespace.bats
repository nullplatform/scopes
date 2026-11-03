#!/usr/bin/env bats
# =============================================================================
# Unit tests for resolve_k8s_namespace - the Kubernetes namespace a scope runs
# in: where it already is, or the configured value, which may be a pattern
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  source "$BATS_TEST_DIRNAME/../resolve_k8s_namespace"

  export KUBECTL_LOG="$(mktemp)"

  # Cluster state the kubectl mock answers from
  export MOCK_SCOPE_NS=""   # namespace where the scope already has objects
  export MOCK_PODS_NS=""    # namespace of the pods matching a selector

  kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    case "$*" in
      "get deployments,services,cronjobs,jobs -A -l scope_id="*)
        printf '%s' "$MOCK_SCOPE_NS" ;;
      "get pods -A -l "*)
        printf '%s' "$MOCK_PODS_NS" ;;
      *)
        return 0 ;;
    esac
  }
  export -f kubectl

  export CONTEXT='{
    "scope": {"id": "scope-1", "dimensions": {"environment": "production"}},
    "namespace": {"id": 300, "slug": "payments"},
    "account": {"id": 20, "slug": "acme"}
  }'
}

teardown() {
  rm -f "$KUBECTL_LOG"
  unset -f kubectl log
}

# =============================================================================
# A plain namespace: behaviour is unchanged
# =============================================================================
@test "resolve_k8s_namespace: a new scope uses a plain configured namespace as is" {
  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "nullplatform"
}

@test "resolve_k8s_namespace: without a scope id it never calls kubectl" {
  CONTEXT=$(echo "$CONTEXT" | jq 'del(.scope.id)')

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "nullplatform"
  assert_equal "$(cat "$KUBECTL_LOG")" ""
}

# =============================================================================
# Existing scopes never move
# =============================================================================
@test "resolve_k8s_namespace: an existing scope stays where its objects are when the configured namespace changes" {
  export MOCK_SCOPE_NS="old-namespace"

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "old-namespace"
}

@test "resolve_k8s_namespace: an existing scope stays where its objects are when a pattern is configured" {
  export MOCK_SCOPE_NS="nullplatform"

  resolve_k8s_namespace "{.namespace.slug}"

  assert_equal "$K8S_NAMESPACE" "nullplatform"
}

@test "resolve_k8s_namespace: looks the scope up by the context scope id" {
  resolve_k8s_namespace "nullplatform"

  assert_contains "$(cat "$KUBECTL_LOG")" "get deployments,services,cronjobs,jobs -A -l scope_id=scope-1"
}

@test "resolve_k8s_namespace: an explicit scope id wins over the context" {
  resolve_k8s_namespace "nullplatform" "scope-from-tags"

  assert_contains "$(cat "$KUBECTL_LOG")" "scope_id=scope-from-tags"
}

@test "resolve_k8s_namespace: falls back to the scope id in the context tags" {
  CONTEXT=$(echo "$CONTEXT" | jq 'del(.scope.id) | .tags.scope_id = "scope-2"')

  resolve_k8s_namespace "nullplatform"

  assert_contains "$(cat "$KUBECTL_LOG")" "scope_id=scope-2"
}

# =============================================================================
# A pattern: one Kubernetes namespace per nullplatform namespace, or any other
# grouping the context allows
# =============================================================================
@test "resolve_k8s_namespace: {.namespace.slug} gives a new scope the nullplatform namespace slug" {
  resolve_k8s_namespace "{.namespace.slug}"

  assert_equal "$K8S_NAMESPACE" "payments"
}

@test "resolve_k8s_namespace: the pattern can prefix the account slug" {
  resolve_k8s_namespace "{.account.slug}-{.namespace.slug}"

  assert_equal "$K8S_NAMESPACE" "acme-payments"
}

@test "resolve_k8s_namespace: the pattern can read scope dimensions" {
  resolve_k8s_namespace "{.namespace.slug}-{.scope.dimensions.environment}"

  assert_equal "$K8S_NAMESPACE" "payments-production"
}

@test "resolve_k8s_namespace: the pattern can carry fixed text" {
  resolve_k8s_namespace "apps-{.namespace.slug}-{.scope.dimensions.environment}-team"

  assert_equal "$K8S_NAMESPACE" "apps-payments-production-team"
}

@test "resolve_k8s_namespace: the pattern can read context tags" {
  CONTEXT=$(echo "$CONTEXT" | jq 'del(.namespace) | .tags = {namespace: "billing"}')

  resolve_k8s_namespace "{.tags.namespace}"

  assert_equal "$K8S_NAMESPACE" "billing"
}

@test "resolve_k8s_namespace: any rendered name is accepted, default included" {
  CONTEXT=$(echo "$CONTEXT" | jq '.namespace.slug = "default"')

  resolve_k8s_namespace "{.namespace.slug}"

  assert_equal "$K8S_NAMESPACE" "default"
}

@test "resolve_k8s_namespace: rejects a pattern the naming engine rejects" {
  run resolve_k8s_namespace "{.namespace.slug}_{.account.slug}"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Could not render the Kubernetes namespace from pattern"
}

@test "resolve_k8s_namespace: rejects a placeholder that is an object, not a single value" {
  run resolve_k8s_namespace "{.namespace.slug}-{.scope.dimensions}"

  [ "$status" -eq 1 ]
  assert_contains "$output" "which is not a valid Kubernetes namespace name"
  assert_contains "$output" "{.scope.dimensions.environment}"
}

@test "resolve_k8s_namespace: rejects a rendered name that is not a valid namespace name" {
  run resolve_k8s_namespace "{.namespace.slug}-"

  [ "$status" -eq 1 ]
  assert_contains "$output" "renders 'payments-', which is not a valid Kubernetes namespace name"
}

@test "resolve_k8s_namespace: fails when the pattern reads a field the context lacks" {
  run resolve_k8s_namespace "{.namespace.slug}-{.scope.dimensions.region}"

  [ "$status" -eq 1 ]
  assert_contains "$output" "resolves to an empty value"
}

# =============================================================================
# Read actions
# =============================================================================
@test "k8s_namespace_of_pods: returns the namespace of the matching pods" {
  export MOCK_PODS_NS="payments"

  assert_equal "$(k8s_namespace_of_pods "application_id=4000")" "payments"
}
