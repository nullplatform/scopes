#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/verify_no_traffic_to_blue
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log
  np_scope_failure() { :; }
  export -f np_scope_failure

  export SCRIPT="$PROJECT_ROOT/k8s/deployment/verify_no_traffic_to_blue"
  export INGRESS_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/istio/initial-httproute.yaml.tpl"
  export K8S_NAMESPACE="apps" SCOPE_ID="123" DEPLOYMENT_ID="2"
  export CONTEXT='{"scope": {"current_active_deployment": "1"}}'
  export INTERNAL_WEIGHT=0

  kubectl() {
    case "$2" in
      service) echo '{"items": [{"metadata": {"name": "d-123-1"}}, {"metadata": {"name": "d-123-1-http-8081"}}]}' ;;
      httproute) cat <<JSON
{"items": [
  {"metadata": {"name": "k-8-s-app-123"}, "spec": {"rules": [{"backendRefs": [
    {"group": "", "kind": "Service", "name": "d-123-2", "port": 8080, "weight": 100}]}]}},
  {"metadata": {"name": "app-scope-http-8081"}, "spec": {"rules": [{"backendRefs": [
    {"group": "", "kind": "Service", "name": "d-123-1-http-8081", "port": 8081, "weight": $INTERNAL_WEIGHT},
    {"group": "", "kind": "Service", "name": "d-123-2-http-8081", "port": 8081, "weight": 100}]}]}}
]}
JSON
      ;;
    esac
  }
  export -f kubectl
}

@test "verify_no_traffic_to_blue: passes when no route sends traffic to the previous deployment" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "verify_no_traffic_to_blue: fails naming every route that still sends it traffic" {
  export INTERNAL_WEIGHT=50

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Routes still send traffic to the previous deployment 1, which finalize would delete:"
  assert_contains "$output" "   - app-scope-http-8081 → d-123-1-http-8081 (weight 50)"
}

@test "verify_no_traffic_to_blue: does nothing for Ingress scopes" {
  export INGRESS_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/initial-ingress.yaml.tpl"
  export INTERNAL_WEIGHT=50

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
}

@test "verify_no_traffic_to_blue: warns and continues when the cluster cannot be read" {
  kubectl() { echo "Forbidden"; return 1; }
  export -f kubectl

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Could not check which routes still send traffic to deployment 1"
}

@test "verify_no_traffic_to_blue: finalize runs it right before deleting the previous deployment" {
  run bash -c "yq '.steps[].name' '$PROJECT_ROOT/k8s/deployment/workflows/finalize.yaml' | grep -A1 -x 'verify no traffic to previous deployment'"
  assert_equal "$output" "verify no traffic to previous deployment
delete deployment"
}
