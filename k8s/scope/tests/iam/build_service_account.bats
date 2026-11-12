#!/usr/bin/env bats
# =============================================================================
# Unit tests for iam/build_service_account - Service account setup from IAM role
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  # Script under test
  export SCRIPT="$BATS_TEST_DIRNAME/../../iam/build_service_account"

  # Default environment variables
  export SCOPE_ID="test-scope-123"
  export OUTPUT_DIR="$(mktemp -d)"
  export SERVICE_ACCOUNT_TEMPLATE="/templates/service_account.yaml"
  export CONTEXT='{"namespace":"test-ns","scope":{"id":"123"}}'

  # Mock aws - default success
  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f aws

  # Mock gomplate - default success
  gomplate() {
    return 0
  }
  export -f gomplate

  # Mock rm
  rm() {
    return 0
  }
  export -f rm
}

teardown() {
  rm -rf "$OUTPUT_DIR" 2>/dev/null || true
  unset -f aws gomplate rm 2>/dev/null || true
}

# =============================================================================
# Test: IAM disabled (ENABLED=false) skips service account setup
# =============================================================================
@test "build_service_account: IAM disabled (ENABLED=false) skips with message" {
  export IAM='{"ENABLED":"false"}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping service account setup"
}

# =============================================================================
# Test: IAM disabled (ENABLED=null) skips service account setup
# =============================================================================
@test "build_service_account: IAM disabled (ENABLED=null) skips with message" {
  export IAM='{"ENABLED":null}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping service account setup"
}

# =============================================================================
# Test: IAM not set defaults to empty JSON and skips
# =============================================================================
@test "build_service_account: IAM not set defaults to empty JSON and skips" {
  unset IAM

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping service account setup"
}

# =============================================================================
# Test: Success flow - finds role, builds template
# =============================================================================
@test "build_service_account: success flow verifies all log messages in order" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "🔍 Looking for IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "📝 Building service account template: /templates/service_account.yaml"
  assert_contains "$output" "✅ Service account template built successfully"
}

# =============================================================================
# Test: Error - aws iam get-role fails (non-delete action)
# =============================================================================
@test "build_service_account: aws iam get-role failure shows error with hints" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "An error occurred (AccessDenied) when calling the GetRole operation" >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "🔍 Looking for IAM role: test-prefix-test-scope-123"
  assert_contains "$output" "❌ Failed to find IAM role 'test-prefix-test-scope-123'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The IAM role may not exist or the agent lacks IAM permissions"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify the role exists: aws iam get-role --role-name test-prefix-test-scope-123"
  assert_contains "$output" "• Check IAM permissions for the agent role"
}

# =============================================================================
# Test: Delete action with NoSuchEntity skips service account deletion
# =============================================================================
@test "build_service_account: delete action with NoSuchEntity skips deletion" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  export ACTION="delete"

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "An error occurred (NoSuchEntity) when calling the GetRole operation: Role with name test-prefix-test-scope-123 cannot be found." >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM role 'test-prefix-test-scope-123' does not exist, skipping service account deletion"
}

# =============================================================================
# Test: Non-delete action with NoSuchEntity fails
# =============================================================================
@test "build_service_account: non-delete action with NoSuchEntity fails with error" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  unset ACTION

  aws() {
    case "$*" in
      *"iam get-role"*)
        echo "An error occurred (NoSuchEntity) when calling the GetRole operation: Role with name test-prefix-test-scope-123 cannot be found." >&2
        return 1
        ;;
    esac
  }
  export -f aws

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to find IAM role 'test-prefix-test-scope-123'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The IAM role may not exist or the agent lacks IAM permissions"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# Test: Error - gomplate template generation fails
# =============================================================================
@test "build_service_account: gomplate failure shows template error with hints" {
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'

  gomplate() {
    echo "Error: template rendering failed" >&2
    return 1
  }
  export -f gomplate

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "📝 Building service account template: /templates/service_account.yaml"
  assert_contains "$output" "❌ Failed to build service account template"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The template file may be missing or contain invalid gomplate syntax"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify template exists: ls -la /templates/service_account.yaml"
  assert_contains "$output" "• Check the template is a valid Kubernetes ServiceAccount YAML with correct gomplate expressions"
}

# =============================================================================
# Per-scope service account (service_account_enabled) — rendered with the real
# template, read from CONTEXT.service_account (not from env vars).
# =============================================================================
sa_context() {
  local enabled="$1" name="$2"
  jq -n --argjson enabled "$enabled" --arg name "$name" '{
    k8s_namespace: "apps-ns",
    account: {slug: "acc", id: 1},
    application: {slug: "app", id: 2},
    namespace: {slug: "ns", id: 3},
    scope: {slug: "scope-a", id: 4},
    k8s_modifiers: {},
    service_account: {enabled: $enabled, name: $name}
  }'
}

use_real_render() {
  unset -f gomplate rm
  export SERVICE_ACCOUNT_TEMPLATE="$PROJECT_ROOT/k8s/scope/templates/service-account.yaml.tpl"
  export SA_FILE="$OUTPUT_DIR/service_account-$SCOPE_ID.yaml"
  # aws must not be reached on the non-IAM path
  aws() { echo "aws called: $*" >&2; return 1; }
  export -f aws
  # Default: the service account does not exist yet
  kubectl() {
    echo "kubectl $*" >> "$BATS_TEST_TMPDIR/kubectl.log"
    [[ " $* " == *" --ignore-not-found "* ]] && return 0
    echo "Error from server (NotFound): serviceaccounts \"$4\" not found" >&2
    return 1
  }
  export -f kubectl
}

# live_sa <scope_id-label|""> : the service account exists, labeled with that scope_id (none when empty)
live_sa() {
  export LIVE_SCOPE_ID="$1"
  kubectl() {
    if [ -n "$LIVE_SCOPE_ID" ]; then
      jq -n --arg id "$LIVE_SCOPE_ID" '{kind:"ServiceAccount",metadata:{name:"app-acc-sa",labels:{scope_id:$id}}}'
    else
      echo '{"kind":"ServiceAccount","metadata":{"name":"app-acc-sa"}}'
    fi
  }
  export -f kubectl
}

@test "build_service_account: IAM off + SA on renders the per-scope service account without role annotation" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_file_exists "$SA_FILE"
  run yq -r '.metadata.name' "$SA_FILE"
  assert_equal "$output" "app-acc-sa"
  run yq -r '.metadata.namespace' "$SA_FILE"
  assert_equal "$output" "apps-ns"
  run yq -r '.metadata.labels.scope_id + "," + .metadata.labels.application_id + "," + .metadata.labels.namespace_id + "," + .metadata.labels.account_id' "$SA_FILE"
  assert_equal "$output" "4,2,3,1"
  run yq -r '.metadata | has("annotations")' "$SA_FILE"
  assert_equal "$output" "false"
  run grep -c "eks.amazonaws.com/role-arn" "$SA_FILE"
  assert_equal "$output" "0"
  run yq -r '.automountServiceAccountToken' "$SA_FILE"
  assert_equal "$output" "true"
}

@test "build_service_account: IAM off + SA on does not call aws" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  [[ "$output" != *"aws called"* ]] || false
}

@test "build_service_account: IAM off + SA off renders nothing (unchanged behavior)" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context false "")"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 IAM is not enabled, skipping service account setup"
  assert_file_not_exists "$SA_FILE"
  run find "$OUTPUT_DIR" -type f
  assert_empty "$output"
}

@test "build_service_account: a CONTEXT without service_account renders nothing" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export CONTEXT='{"k8s_namespace":"apps-ns"}'

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: reads the service account from CONTEXT, not from SERVICE_ACCOUNT_* env vars" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export SERVICE_ACCOUNT_ENABLED=true
  export SERVICE_ACCOUNT_NAME_RESOLVED=from-env
  export CONTEXT="$(sa_context false "")"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_file_not_exists "$SA_FILE"
}


@test "build_service_account: SA enabled with an empty name fails" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true "")"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Service account is enabled but its name is empty"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: IAM on renders the IAM service account with the role annotation" {
  unset -f gomplate rm
  export SERVICE_ACCOUNT_TEMPLATE="$PROJECT_ROOT/k8s/scope/templates/service-account.yaml.tpl"
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  export CONTEXT="$(sa_context false "")"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  SA_FILE="$OUTPUT_DIR/service_account-$SCOPE_ID.yaml"
  run yq -r '.metadata.name' "$SA_FILE"
  assert_equal "$output" "test-prefix-test-scope-123"
  run yq -r '.metadata.annotations["eks.amazonaws.com/role-arn"]' "$SA_FILE"
  assert_equal "$output" "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"
}

@test "build_service_account: SERVICE_ACCOUNT_MODE=per-scope-only leaves the IAM service account to the scope workflows" {
  use_real_render
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  export SERVICE_ACCOUNT_MODE=per-scope-only
  export CONTEXT="$(sa_context false "")"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  [[ "$output" != *"aws called"* ]] || false
  assert_contains "$output" "📋 IAM service account is managed by the scope workflows, skipping"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: SERVICE_ACCOUNT_MODE=per-scope-only still renders the per-scope service account" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export SERVICE_ACCOUNT_MODE=per-scope-only
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  run yq -r '.metadata.name' "$SA_FILE"
  assert_equal "$output" "app-acc-sa"
}

# =============================================================================
# Ownership by the scope_id label (per-scope path only)
# =============================================================================
@test "build_service_account: absent service account is looked up read-only and rendered" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_file_exists "$SA_FILE"
  run cat "$BATS_TEST_TMPDIR/kubectl.log"
  assert_equal "$output" "kubectl get serviceaccount app-acc-sa -n apps-ns -o json --ignore-not-found"
}

@test "build_service_account: service account owned by this scope is rendered" {
  use_real_render
  live_sa 4
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  run yq -r '.metadata.labels.scope_id' "$SA_FILE"
  assert_equal "$output" "4"
}

@test "build_service_account: service account owned by another scope fails on create" {
  use_real_render
  live_sa 99
  export IAM='{"ENABLED":false}'
  export ACTION=create
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Service account 'app-acc-sa' in namespace 'apps-ns' belongs to scope 99"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" '• Make the name unique per scope, e.g. include ${np.scope_id} in security.service_account_name'
  assert_contains "$output" "• To share a service account deliberately, pre-create it in the namespace without a scope_id label"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: service account owned by another scope fails on the deployment ensure step" {
  use_real_render
  live_sa 99
  export IAM='{"ENABLED":false}'
  export ACTION=create SERVICE_ACCOUNT_MODE=per-scope-only
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "belongs to scope 99"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: unlabeled service account is used as-is with a warning" {
  use_real_render
  live_sa ""
  export IAM='{"ENABLED":false}'
  export ACTION=create
  export CONTEXT="$(sa_context true app-acc-sa)"
  # the warning must survive a logger that filters debug and info
  log() { case "$1" in debug|info) return 0 ;; esac; echo "$1: $2"; }
  export -f log

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "warn: ⚠️  Using existing unmanaged service account 'app-acc-sa' in namespace 'apps-ns' as-is (no scope_id label: never modified or deleted by this scope)"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: delete renders the service account owned by this scope" {
  use_real_render
  live_sa 4
  export IAM='{"ENABLED":false}'
  export ACTION=delete
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  run yq -r '.metadata.name' "$SA_FILE"
  assert_equal "$output" "app-acc-sa"
}

@test "build_service_account: delete leaves a foreign service account in place" {
  use_real_render
  live_sa 99
  export IAM='{"ENABLED":false}'
  export ACTION=delete
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "is not owned by scope 4, leaving it in place"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: delete leaves an unlabeled service account in place" {
  use_real_render
  live_sa ""
  export IAM='{"ENABLED":false}'
  export ACTION=delete
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: delete of an absent service account renders nothing" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export ACTION=delete
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Service account 'app-acc-sa' does not exist in namespace 'apps-ns', nothing to delete"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: a kubectl error other than NotFound fails" {
  use_real_render
  kubectl() { echo "error: You must be logged in to the server (Unauthorized)" >&2; return 1; }
  export -f kubectl
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to read service account 'app-acc-sa' in namespace 'apps-ns': error: You must be logged in to the server (Unauthorized)"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: the IAM path never looks up the service account with kubectl" {
  use_real_render
  aws() { echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"; }
  export -f aws
  kubectl() { echo "kubectl called" >&2; return 1; }
  export -f kubectl
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  export CONTEXT="$(sa_context false "")"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  [[ "$output" != *"kubectl called"* ]] || false
}

@test "build_service_account: a kubectl warning on stderr does not corrupt the ownership lookup" {
  use_real_render
  kubectl() {
    echo "Warning: kubectl client version is newer than the server" >&2
    jq -n '{kind:"ServiceAccount",metadata:{name:"app-acc-sa",labels:{scope_id:"4"}}}'
  }
  export -f kubectl
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  run yq -r '.metadata.labels.scope_id' "$SA_FILE"
  assert_equal "$output" "4"
}

@test "build_service_account: any non-zero kubectl exit is an error, even with NotFound on stderr" {
  use_real_render
  kubectl() {
    echo 'Error from server (NotFound): namespaces "apps-ns" not found' >&2
    return 1
  }
  export -f kubectl
  export IAM='{"ENABLED":false}'
  export ACTION=create
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to read service account 'app-acc-sa' in namespace 'apps-ns'"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: delete with a kubectl read error warns and succeeds without deleting" {
  use_real_render
  kubectl() { echo "error: You must be logged in to the server (Unauthorized)" >&2; return 1; }
  export -f kubectl
  export IAM='{"ENABLED":false}'
  export ACTION=delete
  export CONTEXT="$(sa_context true app-acc-sa)"
  log() { case "$1" in debug|info) return 0 ;; esac; echo "$1: $2"; }
  export -f log

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "warn: ⚠️  Could not read service account 'app-acc-sa' in namespace 'apps-ns' (error: You must be logged in to the server (Unauthorized)); leaving it in place, it may be orphaned"
  [[ "$output" != *"❌"* ]] || false
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: the lookup temp file is removed on success and on error" {
  use_real_render
  export TMPDIR="$BATS_TEST_TMPDIR/tmp" && mkdir -p "$TMPDIR"
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "0"
  assert_equal "$(ls -A "$TMPDIR")" ""

  kubectl() { echo "boom" >&2; return 1; }
  export -f kubectl
  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "1"
  assert_equal "$(ls -A "$TMPDIR")" ""
}

@test "build_service_account: the rendering context file is removed when gomplate fails" {
  use_real_render
  gomplate() { echo "Error: template rendering failed" >&2; return 1; }
  export -f gomplate
  export IAM='{"ENABLED":false}'
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_file_not_exists "$OUTPUT_DIR/context-$SCOPE_ID.json"
}

@test "build_service_account: empty scope id fails on create without looking up or rendering" {
  use_real_render
  export IAM='{"ENABLED":false}'
  export ACTION=create
  export CONTEXT="$(sa_context true app-acc-sa | jq '.scope.id = null')"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Scope id is missing from the context, cannot decide who owns service account 'app-acc-sa'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
  assert_file_not_exists "$SA_FILE"
  assert_file_not_exists "$BATS_TEST_TMPDIR/kubectl.log"
}

@test "build_service_account: empty scope id on delete leaves an unlabeled service account in place" {
  use_real_render
  live_sa ""
  export IAM='{"ENABLED":false}'
  export ACTION=delete
  export CONTEXT="$(sa_context true app-acc-sa | jq '.scope.id = ""')"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  assert_contains "$output" "⚠️  Scope id is missing from the context, leaving service account 'app-acc-sa' in place"
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: IAM and per-scope SA both enabled fails on scope create" {
  use_real_render
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  export ACTION=create
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ IAM and service_account_enabled are both enabled for this scope"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• Disable security.iam_enabled or security.service_account_enabled in scope-configurations"
  [[ "$output" != *"aws called"* ]] || false
  assert_file_not_exists "$SA_FILE"
}

@test "build_service_account: IAM and per-scope SA both enabled fails on the deployment ensure step" {
  use_real_render
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  export ACTION=create SERVICE_ACCOUNT_MODE=per-scope-only
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "1"
  assert_contains "$output" "❌ IAM and service_account_enabled are both enabled for this scope"
}

@test "build_service_account: IAM and per-scope SA both enabled does not block scope delete" {
  use_real_render
  aws() { echo "arn:aws:iam::123456789012:role/test-prefix-test-scope-123"; }
  export -f aws
  export IAM='{"ENABLED":"true","PREFIX":"test-prefix"}'
  export ACTION=delete
  export CONTEXT="$(sa_context true app-acc-sa)"

  run bash -c 'source "$SCRIPT"'

  assert_equal "$status" "0"
  run yq -r '.metadata.name' "$SA_FILE"
  assert_equal "$output" "test-prefix-test-scope-123"
}
