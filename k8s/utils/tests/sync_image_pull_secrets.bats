#!/usr/bin/env bats
# =============================================================================
# Unit tests for sync_image_pull_secrets - copies image pull secrets into the
# namespace a scope deploys to when it is not the namespace holding them
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  source "$BATS_TEST_DIRNAME/../sync_image_pull_secrets"

  export KUBECTL_CALLS="$BATS_TEST_TMPDIR/kubectl_calls"
  export APPLIED_DIR="$BATS_TEST_TMPDIR/applied"
  mkdir -p "$APPLIED_DIR"
  export MOCK_MISSING_SECRETS=""
  export MOCK_APPLY_FAILS=""
  export MOCK_REGISTRY="registry.example.com"

  kubectl() {
    echo "kubectl $*" >> "$KUBECTL_CALLS"
    case "$*" in
      "get secret "*" -o json")
        local name="$3" namespace="$5"
        [[ " $MOCK_MISSING_SECRETS " == *" $name "* ]] && { echo "Error from server (NotFound)" >&2; return 1; }
        local config
        config=$(jq -cn --arg r "$MOCK_REGISTRY" '{auths: {($r): {auth: "dXNlcjpwYXNz"}}}' | base64 | tr -d '\n')
        jq -n --arg name "$name" --arg ns "$namespace" --arg config "$config" '{
          apiVersion: "v1", kind: "Secret", type: "kubernetes.io/dockerconfigjson",
          metadata: {
            name: $name, namespace: $ns, uid: "abc", resourceVersion: "42",
            creationTimestamp: "2026-01-01T00:00:00Z", managedFields: [{manager: "kubectl"}],
            ownerReferences: [{kind: "Other"}], selfLink: "/x",
            labels: {team: "platform"},
            annotations: {"kubectl.kubernetes.io/last-applied-configuration": "{}", keep: "me"}
          },
          data: {".dockerconfigjson": $config}
        }'
        ;;
      "apply -n "*" -f -")
        [ -n "$MOCK_APPLY_FAILS" ] && { cat >/dev/null; echo "Error from server (Forbidden)" >&2; return 1; }
        local applied
        applied=$(cat)
        echo "$applied" > "$APPLIED_DIR/$(echo "$applied" | jq -r .metadata.name).json"
        ;;
    esac
  }
  export -f kubectl

  export CONTEXT='{"providers": {}}'
  export K8S_NAMESPACE="nullplatform"
  export PULL_SECRETS_CONFIG='{"ENABLED": true, "SECRETS": ["regcred"]}'
}

teardown() {
  unset IMAGE_PULL_SECRETS_SYNC PULL_SECRET_SOURCE_NAMESPACE NAMESPACE_OVERRIDE
}

# =============================================================================
# Copy
# =============================================================================
@test "sync_image_pull_secrets: copies the secret from the static namespace without server-owned metadata" {
  run sync_image_pull_secrets "$PULL_SECRETS_CONFIG" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Syncing pull secret 'regcred' from 'nullplatform' to 'payments'..."
  assert_contains "$output" "   ✅ Pull secret 'regcred' synced to 'payments'"
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get secret regcred -n nullplatform -o json"
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl apply -n payments -f -"

  local expected_metadata='{
    "name": "regcred",
    "labels": {"team": "platform", "nullplatform.com/synced-from": "nullplatform"},
    "annotations": {"keep": "me"}
  }'
  assert_json_equal "$(jq .metadata "$APPLIED_DIR/regcred.json")" "$expected_metadata" "copied metadata"
  assert_equal "$(jq -r .type "$APPLIED_DIR/regcred.json")" "kubernetes.io/dockerconfigjson"
}

@test "sync_image_pull_secrets: accepts a plain list of secret names" {
  run sync_image_pull_secrets '["regcred", "other"]' "payments"

  [ "$status" -eq 0 ]
  assert_file_exists "$APPLIED_DIR/regcred.json"
  assert_file_exists "$APPLIED_DIR/other.json"
}

@test "sync_image_pull_secrets: follows a customised static namespace" {
  export K8S_NAMESPACE="platform-shared"

  run sync_image_pull_secrets "$PULL_SECRETS_CONFIG" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get secret regcred -n platform-shared -o json"
}

@test "sync_image_pull_secrets: source namespace can be overridden by env" {
  export PULL_SECRET_SOURCE_NAMESPACE="registry-creds"

  run sync_image_pull_secrets "$PULL_SECRETS_CONFIG" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get secret regcred -n registry-creds -o json"
}

@test "sync_image_pull_secrets: source namespace can be overridden by the scope-configurations provider" {
  export CONTEXT='{"providers": {"scope-configurations": {"security": {"pull_secret_source_namespace": "provider-creds"}}}}'

  run sync_image_pull_secrets "$PULL_SECRETS_CONFIG" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_CALLS")" "kubectl get secret regcred -n provider-creds -o json"
}

# =============================================================================
# No-ops
# =============================================================================
@test "sync_image_pull_secrets: does nothing when the target is the source namespace" {
  run sync_image_pull_secrets "$PULL_SECRETS_CONFIG" "nullplatform"

  [ "$status" -eq 0 ]
  assert_file_not_exists "$KUBECTL_CALLS"
}

@test "sync_image_pull_secrets: does nothing when pull secrets are disabled" {
  run sync_image_pull_secrets '{"ENABLED": false, "SECRETS": ["regcred"]}' "payments"

  [ "$status" -eq 0 ]
  assert_file_not_exists "$KUBECTL_CALLS"
}

@test "sync_image_pull_secrets: does nothing when there are no pull secrets configured" {
  run sync_image_pull_secrets "" "payments"

  [ "$status" -eq 0 ]
  assert_file_not_exists "$KUBECTL_CALLS"
}

@test "sync_image_pull_secrets: does nothing when syncing is turned off (external sync such as Kyverno)" {
  export IMAGE_PULL_SECRETS_SYNC="false"

  run sync_image_pull_secrets "$PULL_SECRETS_CONFIG" "payments"

  [ "$status" -eq 0 ]
  assert_file_not_exists "$KUBECTL_CALLS"
}

# =============================================================================
# Missing source secret (IAM-based pulls) and expiring credentials
# =============================================================================
@test "sync_image_pull_secrets: warns and continues when a secret is missing in the source namespace" {
  export MOCK_MISSING_SECRETS="ecr-secret"

  run sync_image_pull_secrets '{"ENABLED": true, "SECRETS": ["ecr-secret", "regcred"]}' "payments"

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  Pull secret 'ecr-secret' not found in namespace 'nullplatform'; skipping it (expected when nodes pull images with IAM)"
  assert_file_not_exists "$APPLIED_DIR/ecr-secret.json"
  assert_file_exists "$APPLIED_DIR/regcred.json"
}

@test "sync_image_pull_secrets: warns that a copied ECR token expires" {
  export MOCK_REGISTRY="235494813897.dkr.ecr.us-east-1.amazonaws.com"

  run sync_image_pull_secrets "$PULL_SECRETS_CONFIG" "payments"

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  Pull secret 'regcred' holds an ECR token, which expires every 12h: its copy in 'payments' is only refreshed on each deploy"
  assert_contains "$output" "   • Prefer pulling with IAM, or keep copies in sync continuously (see k8s/docs/image-pull-secrets.md)"
  assert_file_exists "$APPLIED_DIR/regcred.json"
}

# =============================================================================
# Error scenarios
# =============================================================================
@test "sync_image_pull_secrets: fails with full details when the copy cannot be applied" {
  export MOCK_APPLY_FAILS="true"

  run sync_image_pull_secrets "$PULL_SECRETS_CONFIG" "payments"

  [ "$status" -eq 1 ]
  assert_contains "$output" "   ❌ Failed to sync pull secret 'regcred' to namespace 'payments'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "   • The agent cannot create secrets in namespace 'payments'"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "   • Grant the agent create/patch on secrets cluster-wide, or set IMAGE_PULL_SECRETS_SYNC=false and sync them externally"
}
