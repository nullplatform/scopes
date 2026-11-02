#!/usr/bin/env bats
# =============================================================================
# Unit tests for resolve_k8s_namespace - namespace parity between nullplatform
# namespaces and Kubernetes namespaces
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  source "$BATS_TEST_DIRNAME/../resolve_k8s_namespace"

  export KUBECTL_LOG="$(mktemp)"
  export CREATED_FILE="$(mktemp)"

  # Cluster state the kubectl mock answers from
  export MOCK_SCOPE_NS=""      # namespace where the scope already has objects
  export MOCK_EXISTING_NS=""   # namespace that already exists, by name
  export MOCK_OWNER=""         # namespace_id label of MOCK_EXISTING_NS
  export MOCK_MANAGED=""       # nullplatform label of MOCK_EXISTING_NS
  export MOCK_SOURCE_HAS=""    # "kind/name" objects in the static namespace
  export MOCK_TARGET_HAS=""    # "kind/name" objects in the parity namespace

  kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    case "$*" in
      "get deployments,services -A -l scope_id="*)
        printf '%s' "$MOCK_SCOPE_NS" ;;
      "get namespace "*" -o jsonpath={.metadata.labels.namespace_id}")
        printf '%s' "$MOCK_OWNER" ;;
      "get namespace "*" -o jsonpath={.metadata.labels.nullplatform}")
        printf '%s' "$MOCK_MANAGED" ;;
      "get namespace "*)
        [ "$3" = "$MOCK_EXISTING_NS" ] ;;
      "get pods -A -l "*)
        printf '%s' "${MOCK_PODS_NS:-}" ;;
      "get "*" -n source-ns -o json")
        jq -n --arg ref "$2" --arg type "${MOCK_SECRET_TYPE:-kubernetes.io/dockerconfigjson}" '
          ($ref | split("/")[0]) as $kind
          | {apiVersion: "v1",
             kind: (if $kind == "secret" then "Secret" elif $kind == "configmap" then "ConfigMap" else $kind end),
             metadata: {name: ($ref | split("/")[1]), namespace: "source-ns", uid: "abc", resourceVersion: "1"},
             data: {key: "dmFsdWU="}}
          | if .kind == "Secret" then .type = $type else . end' ;;
      "get "*" -n source-ns")
        [[ " $MOCK_SOURCE_HAS " == *" $2 "* ]] ;;
      "get "*" -n "*)
        [[ " $MOCK_TARGET_HAS " == *" $2 "* ]] ;;
      "create -f -")
        cat >> "$CREATED_FILE" ;;
      *)
        return 0 ;;
    esac
  }
  export -f kubectl

  export CONTEXT='{
    "scope": {"id": "scope-1", "nrn": "organization=1:account=20:namespace=300:application=4000"},
    "namespace": {"id": 300, "slug": "payments"},
    "account": {"id": 20, "slug": "acme"},
    "providers": {
      "container-orchestration": {
        "cluster": {"namespace": "nullplatform", "use_nullplatform_namespace": true}
      }
    }
  }'
}

teardown() {
  rm -f "$KUBECTL_LOG" "$CREATED_FILE"
  unset -f kubectl log
  unset MOCK_SECRET_TYPE USE_NULLPLATFORM_NAMESPACE NAMESPACE_PATTERN K8S_RESERVED_NAMESPACES \
    PULL_SECRETS IMAGE_PULL_SECRETS TRAFFIC_MANAGER_CONFIG_MAP NAMESPACE_BOOTSTRAP_RESOURCES
}

parity_off() {
  CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["container-orchestration"].cluster.use_nullplatform_namespace)')
  export CONTEXT
}

# =============================================================================
# Parity off: behaviour is unchanged
# =============================================================================
@test "resolve_k8s_namespace: parity off keeps the static namespace and never calls kubectl" {
  parity_off

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "nullplatform"
  assert_equal "$K8S_NAMESPACE_PARITY" "false"
  assert_equal "$K8S_NAMESPACE_SOURCE" "static"
  assert_equal "$(cat "$KUBECTL_LOG")" ""
}

@test "resolve_k8s_namespace: use_nullplatform_namespace false keeps the static namespace" {
  CONTEXT=$(echo "$CONTEXT" | jq '.providers["container-orchestration"].cluster.use_nullplatform_namespace = false')

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "nullplatform"
  assert_equal "$K8S_NAMESPACE_PARITY" "false"
}

@test "resolve_k8s_namespace: exposes the nullplatform namespace and account ids" {
  parity_off

  resolve_k8s_namespace "nullplatform"

  assert_equal "$NP_NAMESPACE_ID" "300"
  assert_equal "$NP_ACCOUNT_ID" "20"
}

# =============================================================================
# Parity on: how the namespace is chosen
# =============================================================================
@test "resolve_k8s_namespace: new scope gets the nullplatform namespace slug" {
  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "payments"
  assert_equal "$K8S_NAMESPACE_PARITY" "true"
  assert_equal "$K8S_NAMESPACE_SOURCE" "computed"
}

@test "resolve_k8s_namespace: USE_NULLPLATFORM_NAMESPACE env enables parity without the provider flag" {
  parity_off
  export USE_NULLPLATFORM_NAMESPACE=true

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "payments"
}

@test "resolve_k8s_namespace: naming.namespace_pattern enables parity on its own" {
  parity_off
  CONTEXT=$(echo "$CONTEXT" | jq '.providers["container-orchestration"].naming.namespace_pattern = "{.account.slug}-{.namespace.slug}"')

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "acme-payments"
  assert_equal "$K8S_NAMESPACE_PARITY" "true"
}

@test "resolve_k8s_namespace: NAMESPACE_PATTERN env renders with scope dimensions" {
  parity_off
  CONTEXT=$(echo "$CONTEXT" | jq '.scope.dimensions = {environment: "production"}')
  export NAMESPACE_PATTERN="{.namespace.slug}-{.scope.dimensions.environment}"

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "payments-production"
}

@test "resolve_k8s_namespace: the pattern can carry fixed text" {
  CONTEXT=$(echo "$CONTEXT" | jq '.scope.dimensions = {environment: "production"}')
  export NAMESPACE_PATTERN="apps-{.namespace.slug}-{.scope.dimensions.environment}-team"

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "apps-payments-production-team"
}

@test "resolve_k8s_namespace: the pattern can read context tags" {
  CONTEXT=$(echo "$CONTEXT" | jq 'del(.namespace) | .tags = {namespace: "billing", namespace_id: "301"}')
  export NAMESPACE_PATTERN="{.tags.namespace}"

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "billing"
  assert_equal "$NP_NAMESPACE_ID" "301"
}

@test "resolve_k8s_namespace: the provider pattern wins over the env pattern" {
  CONTEXT=$(echo "$CONTEXT" | jq '.providers["container-orchestration"].naming.namespace_pattern = "{.account.slug}-{.namespace.slug}"')
  export NAMESPACE_PATTERN="{.namespace.slug}"

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "acme-payments"
}

@test "resolve_k8s_namespace: the pattern wins over the use_nullplatform_namespace shorthand" {
  export NAMESPACE_PATTERN="np-{.namespace.slug}"

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "np-payments"
}

@test "resolve_k8s_namespace: rejects a pattern the naming engine rejects" {
  export NAMESPACE_PATTERN="{.namespace.slug}_{.account.slug}"

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Could not render the Kubernetes namespace from pattern"
}

@test "resolve_k8s_namespace: rejects a placeholder that is an object, not a single value" {
  CONTEXT=$(echo "$CONTEXT" | jq '.scope.dimensions = {environment: "production"}')
  export NAMESPACE_PATTERN="{.namespace.slug}-{.scope.dimensions}"

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "uses {.scope.dimensions}, which is an object or a list"
  assert_contains "$output" "{.scope.dimensions.environment}"
}

@test "resolve_k8s_namespace: rejects a placeholder that is a list" {
  CONTEXT=$(echo "$CONTEXT" | jq '.scope.domains = ["a.example.com"]')
  export NAMESPACE_PATTERN="{.namespace.slug}-{.scope.domains}"

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "uses {.scope.domains}, which is an object or a list"
}

@test "resolve_k8s_namespace: rejects a rendered name that is not a valid namespace name" {
  export NAMESPACE_PATTERN="{.namespace.slug}-"

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "renders 'payments-', which is not a valid Kubernetes namespace name"
}

@test "resolve_k8s_namespace: fails when the pattern reads a field the context lacks" {
  export NAMESPACE_PATTERN="{.namespace.slug}-{.scope.dimensions.region}"

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "resolves to an empty value"
}

@test "resolve_k8s_namespace: an existing scope stays where its objects are" {
  export MOCK_SCOPE_NS="nullplatform"

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "nullplatform"
  assert_equal "$K8S_NAMESPACE_SOURCE" "sticky"
}

@test "resolve_k8s_namespace: a new scope follows the rendered name, not other namespaces of its owner" {
  CONTEXT=$(echo "$CONTEXT" | jq '.namespace.slug = "payments-renamed"')

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "payments-renamed"
  assert_equal "$K8S_NAMESPACE_SOURCE" "computed"
  [[ "$(cat "$KUBECTL_LOG")" != *"get namespaces -l"* ]]
}

@test "resolve_k8s_namespace: reuses a namespace this nullplatform namespace already owns" {
  export MOCK_EXISTING_NS="payments" MOCK_OWNER="300" MOCK_MANAGED="true"

  resolve_k8s_namespace "nullplatform"

  assert_equal "$K8S_NAMESPACE" "payments"
}

@test "resolve_k8s_namespace: adopts a nullplatform namespace that has no owner yet" {
  export MOCK_EXISTING_NS="payments" MOCK_OWNER="" MOCK_MANAGED="true"

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Adopting existing nullplatform namespace 'payments'"
}

@test "resolve_k8s_namespace: fails when the namespace belongs to another nullplatform namespace" {
  export MOCK_EXISTING_NS="payments" MOCK_OWNER="999" MOCK_MANAGED="true"

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "belongs to another owner (namespace_id='999')"
  assert_contains "$output" "{.account.slug}-{.namespace.slug}"
}

@test "resolve_k8s_namespace: never takes a namespace created outside nullplatform" {
  export MOCK_EXISTING_NS="payments" MOCK_OWNER="" MOCK_MANAGED=""

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "belongs to another owner (namespace_id='none')"
}

@test "resolve_k8s_namespace: rejects reserved namespaces" {
  CONTEXT=$(echo "$CONTEXT" | jq '.namespace.slug = "kube-system"')

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "'kube-system'"
  assert_contains "$output" "is reserved"
}

@test "resolve_k8s_namespace: rejects the static namespace as a parity namespace" {
  CONTEXT=$(echo "$CONTEXT" | jq '.namespace.slug = "nullplatform"')

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "is reserved"
}

@test "resolve_k8s_namespace: fails clearly when the context has no namespace" {
  CONTEXT=$(echo "$CONTEXT" | jq 'del(.namespace) | .scope.nrn = "organization=1:account=20"')

  run resolve_k8s_namespace "nullplatform"

  [ "$status" -eq 1 ]
  assert_contains "$output" "has no nullplatform namespace id"
}

@test "resolve_k8s_namespace: an explicit scope id wins over the context" {
  export MOCK_SCOPE_NS="nullplatform"

  resolve_k8s_namespace "nullplatform" "scope-from-tags"

  assert_contains "$(cat "$KUBECTL_LOG")" "scope_id=scope-from-tags"
}

# =============================================================================
# Claiming the namespace
# =============================================================================
@test "claim_k8s_namespace: labels the namespace with its nullplatform owner" {
  resolve_k8s_namespace "nullplatform"

  claim_k8s_namespace "payments"

  assert_contains "$(cat "$KUBECTL_LOG")" "label namespace payments --overwrite nullplatform=true namespace_id=300 account_id=20"
  assert_contains "$(cat "$KUBECTL_LOG")" "annotate namespace payments --overwrite nullplatform.com/namespace-name=payments"
}

@test "claim_k8s_namespace: fails when another nullplatform namespace claimed it first" {
  resolve_k8s_namespace "nullplatform"
  export MOCK_OWNER="999"

  run claim_k8s_namespace "payments"

  [ "$status" -eq 1 ]
  assert_contains "$output" "was claimed by nullplatform namespace id 999"
}

# =============================================================================
# Copying base resources
# =============================================================================
@test "copy_k8s_namespace_resources: copies pull secrets and the traffic manager ConfigMap" {
  export IMAGE_PULL_SECRETS='{"ENABLED": true, "SECRETS": ["ecr-secret"]}'
  export TRAFFIC_MANAGER_CONFIG_MAP="tm-config"
  export MOCK_SOURCE_HAS="secret/ecr-secret configmap/tm-config"

  copy_k8s_namespace_resources "source-ns" "payments"

  [ "$(jq -s 'length' "$CREATED_FILE")" -eq 2 ]
  [ "$(jq -s -r 'map(.metadata.namespace) | unique | join(",")' "$CREATED_FILE")" = "payments" ]
  [ "$(jq -s -r 'map(.metadata.uid // "none") | unique | join(",")' "$CREATED_FILE")" = "none" ]
  [ "$(jq -s -r '.[0].metadata.labels["nullplatform.com/copied-from"]' "$CREATED_FILE")" = "source-ns" ]
}

@test "copy_k8s_namespace_resources: reads pull secrets from the providers" {
  CONTEXT=$(echo "$CONTEXT" | jq '.providers["container-orchestration"].security.image_pull_secrets = ["regcred"]')
  export MOCK_SOURCE_HAS="secret/regcred"

  copy_k8s_namespace_resources "source-ns" "payments"

  [ "$(jq -s -r '.[0].metadata.name' "$CREATED_FILE")" = "regcred" ]
}

@test "copy_k8s_namespace_resources: copies extra resources listed in the provider" {
  CONTEXT=$(echo "$CONTEXT" | jq '.providers["container-orchestration"].cluster.namespace_bootstrap_resources = ["networkpolicy/default-deny", "limitrange/defaults"]')
  export MOCK_SOURCE_HAS="networkpolicy/default-deny limitrange/defaults"

  copy_k8s_namespace_resources "source-ns" "payments"

  [ "$(jq -s -r 'map(.metadata.name) | sort | join(",")' "$CREATED_FILE")" = "default-deny,defaults" ]
}

@test "copy_k8s_namespace_resources: never copies a secret that is not an image pull secret" {
  export PULL_SECRETS='["agent-credentials"]'
  export MOCK_SOURCE_HAS="secret/agent-credentials"
  export MOCK_SECRET_TYPE="Opaque"

  run copy_k8s_namespace_resources "source-ns" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$output" "secret/agent-credentials is not an image pull secret, skipping"
  [ ! -s "$CREATED_FILE" ]
}

@test "copy_k8s_namespace_resources: extra resources cannot name secrets" {
  CONTEXT=$(echo "$CONTEXT" | jq '.providers["container-orchestration"].cluster.namespace_bootstrap_resources = ["secret/agent-credentials"]')
  export MOCK_SOURCE_HAS="secret/agent-credentials"

  run copy_k8s_namespace_resources "source-ns" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$output" "secret/agent-credentials is not a kind namespace_bootstrap_resources can copy"
  [ ! -s "$CREATED_FILE" ]
}

@test "copy_k8s_namespace_resources: leaves objects that already exist in the target alone" {
  export PULL_SECRETS='["ecr-secret"]'
  export MOCK_SOURCE_HAS="secret/ecr-secret"
  export MOCK_TARGET_HAS="secret/ecr-secret"

  run copy_k8s_namespace_resources "source-ns" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$output" "secret/ecr-secret already exists in 'payments'"
  [ ! -s "$CREATED_FILE" ]
}

@test "copy_k8s_namespace_resources: warns and continues when the source object is missing" {
  export PULL_SECRETS='["missing-secret"]'

  run copy_k8s_namespace_resources "source-ns" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$output" "secret/missing-secret not found in 'source-ns', skipping"
}

@test "copy_k8s_namespace_resources: does nothing when source and target are the same" {
  export PULL_SECRETS='["ecr-secret"]'

  copy_k8s_namespace_resources "nullplatform" "nullplatform"

  assert_equal "$(cat "$KUBECTL_LOG")" ""
}

# =============================================================================
# Read actions
# =============================================================================
@test "k8s_namespace_of_pods: returns the namespace of the matching pods" {
  export MOCK_PODS_NS="payments"

  assert_equal "$(k8s_namespace_of_pods "application_id=4000")" "payments"
}
