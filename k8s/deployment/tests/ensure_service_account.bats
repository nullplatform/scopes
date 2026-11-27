#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/ensure_service_account - the gke service account of
# a scope created before IAM.MODE gke was turned on is built on its deployment
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCRIPT="$BATS_TEST_DIRNAME/../ensure_service_account"
  export SCOPE_ID="555"
  export K8S_NAMESPACE="nullplatform"
  export OUTPUT_DIR="$(mktemp -d)"
  export SERVICE_ACCOUNT_TEMPLATE="/templates/service-account.yaml.tpl"
  export CONTEXT='{"scope":{"id":"555","dimensions":{"environment":"Staging"}},"application":{"id":"123"}}'

  # No service account yet: the scope predates gke mode.
  kubectl() { return 0; }
  export -f kubectl
  # Write the context gomplate would render, to assert on it.
  gomplate() {
    local ctx out
    while [ $# -gt 0 ]; do
      case "$1" in
        -c) ctx="${2#.=}"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    cp "$ctx" "$out"
  }
  export -f gomplate
  aws() { echo "aws must not be called" >&2; return 1; }
  export -f aws
}

teardown() {
  /bin/rm -rf "$OUTPUT_DIR" 2>/dev/null || true
}

@test "ensure_service_account: IAM disabled builds nothing" {
  export IAM='{"ENABLED":false}'
  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "0"
  assert_equal "$(ls "$OUTPUT_DIR" | wc -l | tr -d ' ')" "0"
}

@test "ensure_service_account: irsa mode builds nothing and calls no aws" {
  export IAM='{"ENABLED":true,"PREFIX":"p","ROLE":{"POLICIES":[]}}'
  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "0"
  assert_equal "$(ls "$OUTPUT_DIR" | wc -l | tr -d ' ')" "0"
}

@test "ensure_service_account: gke mode builds np-<app>-<env> in the deployment's namespace" {
  export IAM='{"ENABLED":true,"MODE":"gke","DIMENSION":"environment"}'
  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "0"
  local file="$OUTPUT_DIR/service_account-555.yaml"
  [ -f "$file" ]
  assert_equal "$(jq -r .service_account_name "$file")" "np-123-staging"
  assert_equal "$(jq -r .k8s_namespace "$file")" "nullplatform"
  assert_equal "$(jq -r .iam_mode "$file")" "gke"
  assert_equal "$(jq -r .gke_environment "$file")" "staging"
}

@test "ensure_service_account: gke mode keeps a namespace the context already has" {
  export IAM='{"ENABLED":true,"MODE":"gke"}'
  export CONTEXT='{"k8s_namespace":"apps","scope":{"id":"555","dimensions":{"environment":"dev"}},"application":{"id":"123"}}'
  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "0"
  assert_equal "$(jq -r .k8s_namespace "$OUTPUT_DIR/service_account-555.yaml")" "apps"
}

@test "ensure_service_account: gke mode refuses a service account of another application" {
  export IAM='{"ENABLED":true,"MODE":"gke"}'
  kubectl() { echo '{"metadata":{"labels":{"application_id":"999","environment":"staging"}}}'; }
  export -f kubectl
  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "1"
}

@test "ensure_service_account: a missing dimension fails the deployment with a clear error" {
  export IAM='{"ENABLED":true,"MODE":"gke"}'
  export CONTEXT='{"scope":{"id":"555","dimensions":{}},"application":{"id":"123"}}'
  run bash -c 'source "$SCRIPT"'
  assert_equal "$status" "1"
}
