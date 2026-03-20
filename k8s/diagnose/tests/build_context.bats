#!/usr/bin/env bats
# Unit tests for diagnose/build_context - diagnostic context preparation

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export K8S_NAMESPACE="default-ns"
  export SCOPE_ID="scope-123"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export NP_ACTION_CONTEXT='{}'
  export ALB_CONTROLLER_NAMESPACE="kube-system"

  export CONTEXT='{
    "providers": {
      "container-orchestration": {
        "cluster": {"namespace": "provider-namespace"}
      }
    },
    "parameters": {"deployment_id": "deploy-789"}
  }'

  kubectl() {
    case "$*" in
      *"app.kubernetes.io/name=aws-load-balancer-controller"*) echo '{"items":[]}' ;;
      *"app=aws-alb-ingress-controller"*) echo '{"items":[]}' ;;
      *"get pods"*)        echo '{"items":[{"metadata":{"name":"test-pod"}}]}' ;;
      *"get services"*)    echo '{"items":[{"metadata":{"name":"test-service"}}]}' ;;
      *"get endpoints"*)   echo '{"items":[]}' ;;
      *"get ingress"*)     echo '{"items":[]}' ;;
      *"get secrets"*)     echo '{"items":[]}' ;;
      *"get ingressclass"*) echo '{"items":[]}' ;;
      *"get events"*)      echo '{"items":[]}' ;;
      *"logs"*)            echo "log line 1" ;;
      *)                   echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  notify_results() { return 0; }
  export -f notify_results
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  unset K8S_NAMESPACE SCOPE_ID NP_OUTPUT_DIR NP_ACTION_CONTEXT CONTEXT
  unset LABEL_SELECTOR SCOPE_LABEL_SELECTOR NAMESPACE ALB_CONTROLLER_NAMESPACE
  unset -f kubectl notify_results
}

run_build_context() {
  source "$BATS_TEST_DIRNAME/../build_context"
}

# =============================================================================
# Namespace Resolution
# =============================================================================
@test "build_context: NAMESPACE from provider > K8S_NAMESPACE fallback" {
  # Test provider namespace
  run_build_context
  assert_equal "$NAMESPACE" "provider-namespace"

  # Test fallback
  export CONTEXT='{"providers": {}}'
  run_build_context
  assert_equal "$NAMESPACE" "default-ns"
}

# =============================================================================
# Label Selectors
# =============================================================================
@test "build_context: sets label selectors from various deployment_id sources" {
  # From parameters.deployment_id (default setup)
  run_build_context
  assert_equal "$SCOPE_LABEL_SELECTOR" "scope_id=scope-123"
  assert_equal "$LABEL_SELECTOR" "scope_id=scope-123,deployment_id=deploy-789"

  # From deployment.id
  export CONTEXT='{"providers": {}, "deployment": {"id": "deploy-from-deployment"}}'
  run_build_context
  assert_equal "$LABEL_SELECTOR" "scope_id=scope-123,deployment_id=deploy-from-deployment"

  # From scope.current_active_deployment
  export CONTEXT='{"providers": {}, "scope": {"current_active_deployment": "deploy-active"}}'
  run_build_context
  assert_equal "$LABEL_SELECTOR" "scope_id=scope-123,deployment_id=deploy-active"

  # No deployment_id - LABEL_SELECTOR equals SCOPE_LABEL_SELECTOR
  export CONTEXT='{"providers": {}, "parameters": {}}'
  run_build_context
  assert_equal "$LABEL_SELECTOR" "scope_id=scope-123"
}

# =============================================================================
# Directory and File Creation
# =============================================================================
@test "build_context: creates data directory and all resource files" {
  run_build_context

  assert_directory_exists "$NP_OUTPUT_DIR/data"
  assert_directory_exists "$NP_OUTPUT_DIR/data/alb_controller_logs"

  # All resource files should exist and be valid JSON
  for file in "$PODS_FILE" "$SERVICES_FILE" "$ENDPOINTS_FILE" "$INGRESSES_FILE" \
              "$SECRETS_FILE" "$INGRESSCLASSES_FILE" "$EVENTS_FILE" "$ALB_CONTROLLER_PODS_FILE"; do
    assert_file_exists "$file"
    jq . "$file" >/dev/null
  done
}

@test "build_context: secrets.json excludes sensitive data field" {
  kubectl() {
    case "$*" in
      *"get secrets"*)
        echo '{"items":[{"metadata":{"name":"my-secret"},"data":{"password":"c2VjcmV0"}}]}'
        ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  assert_file_exists "$SECRETS_FILE"
  has_data=$(jq '.items[0].data // empty' "$SECRETS_FILE")
  assert_empty "$has_data"
}

# =============================================================================
# Empty Results Handling
# =============================================================================
@test "build_context: handles kubectl returning empty results" {
  kubectl() { echo '{"items":[]}'; }
  export -f kubectl

  run_build_context

  assert_file_exists "$PODS_FILE"
  items_count=$(jq '.items | length' "$PODS_FILE")
  assert_equal "$items_count" "0"
}

# =============================================================================
# ALB Controller Discovery
# =============================================================================
@test "build_context: tries legacy ALB controller label when new one has no pods" {
  kubectl() {
    case "$*" in
      *"app.kubernetes.io/name=aws-load-balancer-controller"*)
        echo '{"items":[]}'
        ;;
      *"app=aws-alb-ingress-controller"*)
        echo '{"items":[{"metadata":{"name":"legacy-alb-pod"}}]}'
        ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  content=$(cat "$ALB_CONTROLLER_PODS_FILE")
  assert_contains "$content" "legacy-alb-pod"
}

@test "build_context: collects ALB controller logs when pods exist" {
  kubectl() {
    case "$*" in
      *"app.kubernetes.io/name=aws-load-balancer-controller"*)
        echo '{"items":[{"metadata":{"name":"alb-controller-pod"}}]}'
        ;;
      *"logs"*"alb-controller-pod"*)
        echo "controller log line"
        ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  assert_file_exists "$ALB_CONTROLLER_LOGS_DIR/alb-controller-pod.log"
  log_content=$(cat "$ALB_CONTROLLER_LOGS_DIR/alb-controller-pod.log")
  assert_contains "$log_content" "controller log line"
}
