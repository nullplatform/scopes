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
      *"get deployment"*)  echo '{"items":[{"metadata":{"name":"test-deployment"}}]}' ;;
      *"get rs"*)          echo '{"items":[{"metadata":{"name":"test-rs"}}]}' ;;
      *"get services"*)    echo '{"items":[{"metadata":{"name":"test-service"}}]}' ;;
      *"get endpoints"*)   echo '{"items":[]}' ;;
      *"get ingress"*)     echo '{"items":[]}' ;;
      *"get secrets"*)     echo '{"items":[]}' ;;
      *"get ingressclass"*) echo '{"items":[]}' ;;
      *"get events"*)      echo '{"items":[]}' ;;
      *"describe pod"*)    echo "Pod describe output" ;;
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
  assert_directory_exists "$POD_LOGS_DIR"
  assert_directory_exists "$POD_DESCRIBE_DIR"

  # All resource files should exist and be valid JSON
  for file in "$PODS_FILE" "$DEPLOYMENTS_FILE" "$REPLICASETS_FILE" "$SERVICES_FILE" \
              "$ENDPOINTS_FILE" "$INGRESSES_FILE" "$SECRETS_FILE" "$INGRESSCLASSES_FILE" \
              "$EVENTS_FILE" "$ALB_CONTROLLER_PODS_FILE"; do
    assert_file_exists "$file"
    jq . "$file" >/dev/null
  done

  # problematic_pods.txt is plain text, just assert it exists
  assert_file_exists "$PROBLEMATIC_PODS_FILE"
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

# =============================================================================
# Problematic Pod Detection
# =============================================================================
@test "build_context: healthy running pod is not flagged as problematic" {
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"healthy-pod"},
          "spec":{"containers":[{"name":"app"}]},
          "status":{
            "phase":"Running",
            "conditions":[{"type":"Ready","status":"True"}],
            "containerStatuses":[{"name":"app","restartCount":0,"state":{"running":{}},"lastState":{}}]
          }
        }]}'
        ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  problematic=$(cat "$PROBLEMATIC_PODS_FILE")
  assert_empty "$problematic"
}

@test "build_context: pod in CrashLoopBackOff is flagged as problematic" {
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"crash-pod"},
          "spec":{"containers":[{"name":"app"}]},
          "status":{
            "phase":"Running",
            "conditions":[{"type":"Ready","status":"False"}],
            "containerStatuses":[{"name":"app","restartCount":5,"state":{"waiting":{"reason":"CrashLoopBackOff"}},"lastState":{"terminated":{"exitCode":1}}}]
          }
        }]}'
        ;;
      *"describe pod crash-pod"*) echo "describe output for crash-pod" ;;
      *"logs"*"crash-pod"*"--previous"*) echo "previous crash log" ;;
      *"logs"*"crash-pod"*) echo "current log" ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  problematic=$(cat "$PROBLEMATIC_PODS_FILE")
  assert_contains "$problematic" "crash-pod"
}

@test "build_context: pod in Pending phase is flagged as problematic" {
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"pending-pod"},
          "spec":{"containers":[{"name":"app"}]},
          "status":{"phase":"Pending"}
        }]}'
        ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  problematic=$(cat "$PROBLEMATIC_PODS_FILE")
  assert_contains "$problematic" "pending-pod"
}

@test "build_context: pod with terminating deletionTimestamp is flagged as problematic" {
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"terminating-pod","deletionTimestamp":"2026-01-01T00:00:00Z"},
          "spec":{"containers":[{"name":"app"}]},
          "status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}],"containerStatuses":[{"name":"app","restartCount":0,"state":{"running":{}},"lastState":{}}]}
        }]}'
        ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  problematic=$(cat "$PROBLEMATIC_PODS_FILE")
  assert_contains "$problematic" "terminating-pod"
}

@test "build_context: pod with failed init container is flagged as problematic" {
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"init-fail-pod"},
          "spec":{"initContainers":[{"name":"init-db"}],"containers":[{"name":"app"}]},
          "status":{
            "phase":"Pending",
            "initContainerStatuses":[{"name":"init-db","restartCount":3,"state":{"waiting":{"reason":"CrashLoopBackOff"}},"lastState":{"terminated":{"exitCode":1}}}]
          }
        }]}'
        ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  problematic=$(cat "$PROBLEMATIC_PODS_FILE")
  assert_contains "$problematic" "init-fail-pod"
}

# =============================================================================
# Pod Logs and Describe Capture
# =============================================================================
@test "build_context: captures describe and current logs for problematic pod" {
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"crash-pod"},
          "spec":{"containers":[{"name":"app"}]},
          "status":{
            "phase":"Running",
            "containerStatuses":[{"name":"app","restartCount":2,"state":{"waiting":{"reason":"CrashLoopBackOff"}},"lastState":{"terminated":{"exitCode":1}}}]
          }
        }]}'
        ;;
      *"describe pod crash-pod"*) echo "describe output for crash-pod" ;;
      *"logs"*"crash-pod"*"--previous"*) echo "previous crash log" ;;
      *"logs"*"crash-pod"*) echo "current log line" ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  assert_file_exists "$POD_DESCRIBE_DIR/crash-pod.txt"
  describe_content=$(cat "$POD_DESCRIBE_DIR/crash-pod.txt")
  assert_contains "$describe_content" "describe output for crash-pod"

  assert_file_exists "$POD_LOGS_DIR/crash-pod.app.log"
  current_log=$(cat "$POD_LOGS_DIR/crash-pod.app.log")
  assert_contains "$current_log" "current log line"

  assert_file_exists "$POD_LOGS_DIR/crash-pod.app.previous.log"
  previous_log=$(cat "$POD_LOGS_DIR/crash-pod.app.previous.log")
  assert_contains "$previous_log" "previous crash log"
}

@test "build_context: skips empty previous logs (container never crashed before)" {
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"new-pod"},
          "spec":{"containers":[{"name":"app"}]},
          "status":{
            "phase":"Pending",
            "containerStatuses":[{"name":"app","restartCount":0,"state":{"waiting":{"reason":"ImagePullBackOff"}},"lastState":{}}]
          }
        }]}'
        ;;
      *"describe pod new-pod"*) echo "describe output" ;;
      *"logs"*"new-pod"*"--previous"*) return 1 ;;
      *"logs"*"new-pod"*) echo "current log" ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  # Current log should be saved
  assert_file_exists "$POD_LOGS_DIR/new-pod.app.log"

  # Previous log should NOT exist (kubectl returned no output)
  [ ! -f "$POD_LOGS_DIR/new-pod.app.previous.log" ]
}

@test "build_context: captures logs for all containers including init containers" {
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"multi-container-pod"},
          "spec":{
            "initContainers":[{"name":"init-db"}],
            "containers":[{"name":"app"},{"name":"sidecar"}]
          },
          "status":{
            "phase":"Pending",
            "initContainerStatuses":[{"name":"init-db","restartCount":1,"state":{"waiting":{"reason":"CrashLoopBackOff"}},"lastState":{"terminated":{"exitCode":1}}}]
          }
        }]}'
        ;;
      *"describe pod multi-container-pod"*) echo "describe output" ;;
      *"logs"*"-c init-db"*"--previous"*) echo "init previous" ;;
      *"logs"*"-c init-db"*) echo "init current" ;;
      *"logs"*"-c app"*"--previous"*) return 1 ;;
      *"logs"*"-c app"*) echo "app current" ;;
      *"logs"*"-c sidecar"*"--previous"*) return 1 ;;
      *"logs"*"-c sidecar"*) echo "sidecar current" ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  # All three containers' current logs should exist
  assert_file_exists "$POD_LOGS_DIR/multi-container-pod.init-db.log"
  assert_file_exists "$POD_LOGS_DIR/multi-container-pod.app.log"
  assert_file_exists "$POD_LOGS_DIR/multi-container-pod.sidecar.log"

  # Only init-db has a previous log
  assert_file_exists "$POD_LOGS_DIR/multi-container-pod.init-db.previous.log"
  [ ! -f "$POD_LOGS_DIR/multi-container-pod.app.previous.log" ]
  [ ! -f "$POD_LOGS_DIR/multi-container-pod.sidecar.previous.log" ]
}

@test "build_context: respects POD_LOG_TAIL_LINES env var" {
  export POD_LOG_TAIL_LINES=42

  # Capture the kubectl invocation to verify --tail value
  kubectl() {
    case "$*" in
      *"get pods"*)
        echo '{"items":[{
          "metadata":{"name":"crash-pod"},
          "spec":{"containers":[{"name":"app"}]},
          "status":{"phase":"Pending","containerStatuses":[{"name":"app","restartCount":1,"state":{"waiting":{"reason":"ImagePullBackOff"}},"lastState":{}}]}
        }]}'
        ;;
      *"logs"*"--tail=42"*) echo "tail-42-honored" ;;
      *"logs"*) echo "WRONG: tail value was not 42" ;;
      *"describe"*) echo "describe" ;;
      *) echo '{"items":[]}' ;;
    esac
  }
  export -f kubectl

  run_build_context

  log_content=$(cat "$POD_LOGS_DIR/crash-pod.app.log")
  assert_contains "$log_content" "tail-42-honored"

  unset POD_LOG_TAIL_LINES
}
