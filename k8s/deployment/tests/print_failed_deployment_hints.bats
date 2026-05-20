#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/print_failed_deployment_hints - error hints display
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export CONTEXT='{
    "scope": {
      "name": "my-app",
      "dimensions": "production",
      "capabilities": {
        "health_check": {
          "path": "/health"
        },
        "ram_memory": 512
      }
    }
  }'
}

teardown() {
  unset CONTEXT
  unset K8S_NAMESPACE DEPLOYMENT_ID ALL_EVENTS desired ready current
  unset -f kubectl 2>/dev/null || true
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Expected output to NOT contain: '$needle'"
    echo "Actual: '$haystack'"
    return 1
  fi
}

# =============================================================================
# Generic Hints (no diagnostic context available)
# =============================================================================
@test "print_failed_deployment_hints: displays generic hints when no diagnostic context available" {
  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  # Main header
  assert_contains "$output" "⚠️  Application Startup Issue Detected"
  # Possible causes
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Your application was unable to start"
  # How to fix section
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "port 8080"
  assert_contains "$output" "/health"
  assert_contains "$output" "Application Logs"
  assert_contains "$output" "512Mi"
  assert_contains "$output" "Environment Variables"
  assert_contains "$output" "my-app"
  assert_contains "$output" "production"
}

# =============================================================================
# Pod-derived Diagnostics
# =============================================================================
@test "print_failed_deployment_hints: identifies OOMKilled and skips generic hints" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"app","state":{"running":{}},"lastState":{"terminated":{"reason":"OOMKilled","exitCode":137,"message":"out of memory"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: The container exceeded its memory limit (512Mi)"
  assert_contains "$output" "📋 Detected: OOMKilled on container app (exit 137)"
  assert_contains "$output" "📋 Details: out of memory"
  assert_contains "$output" "💡 Suggested fix: Increase ram_memory for scope 'my-app'"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies ImagePullBackOff from waiting state without exit code" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"web","state":{"waiting":{"reason":"ImagePullBackOff","message":"manifest unknown"}},"lastState":{}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: The container image could not be pulled."
  assert_contains "$output" "📋 Detected: ImagePullBackOff on container web"
  assert_not_contains "$output" "exit "
  assert_contains "$output" "📋 Details: manifest unknown"
  assert_contains "$output" "💡 Suggested fix: Verify the image name, tag, and registry credentials"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies CrashLoopBackOff and skips generic hints" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"worker","state":{"waiting":{"reason":"CrashLoopBackOff","message":"back-off 5m0s restarting failed container"}},"lastState":{"terminated":{"exitCode":1}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: The container started and crashed repeatedly."
  assert_contains "$output" "📋 Detected: CrashLoopBackOff on container worker"
  assert_contains "$output" "💡 Suggested fix: Review application logs for startup errors"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies CreateContainerConfigError and points to secrets/configmaps" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"api","state":{"waiting":{"reason":"CreateContainerConfigError","message":"secret \"db-creds\" not found"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: The container configuration is invalid."
  assert_contains "$output" "💡 Suggested fix: Check for missing secrets or configmaps"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies RunContainerError as entrypoint failure" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"app","state":{"waiting":{"reason":"RunContainerError"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: The container failed to run its entrypoint."
  assert_contains "$output" "💡 Suggested fix: Verify the start command"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies ContainerCannotRun as missing binary" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"app","state":{"running":{}},"lastState":{"terminated":{"reason":"ContainerCannotRun","exitCode":127,"message":"exec: \"/app\": no such file"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: The startup binary is missing or not executable"
  assert_contains "$output" "📋 Detected: ContainerCannotRun on container app (exit 127)"
  assert_contains "$output" "💡 Suggested fix: Rebuild the image"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies FailedMount from ALL_EVENTS" {
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"FailedMount","message":"MountVolume.SetUp failed"}]}'

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: A volume could not be mounted onto the pod."
  assert_contains "$output" "💡 Suggested fix: Check that the referenced PVC, secret, or configmap exists"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies FailedCreatePodSandBox from ALL_EVENTS" {
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"FailedCreatePodSandBox","message":"failed to create pod sandbox"}]}'

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: Kubernetes could not create the pod sandbox."
  assert_contains "$output" "💡 Suggested fix: Check node health, CNI configuration"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies Unhealthy and references the configured health check path" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"api","state":{"waiting":{"reason":"Unhealthy"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "did not pass its health check at /health"
  assert_contains "$output" "💡 Suggested fix: Ensure the app listens on port 8080 and returns 2xx on /health"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: enriches Unhealthy with connection-refused detail and targeted fix" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"Unhealthy","lastTimestamp":"2026-05-20T13:13:42Z","message":"Startup probe failed: Get \"http://10.0.0.1:8080/health\": dial tcp 10.0.0.1:8080: connect: connection refused"}]}'

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"api","state":{"waiting":{"reason":"Unhealthy"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  # HUMAN_MESSAGE retains the base sentence and appends the translated probe failure
  assert_contains "$output" "did not pass its health check at /health"
  assert_contains "$output" "Detected: Startup probe"
  assert_contains "$output" "not yet listening"
  # SUGGESTED_FIX is targeted: tells the user the app is not binding the port
  assert_contains "$output" "not listening on port 8080"
  # Generic fallback fix must NOT appear
  assert_not_contains "$output" "returns 2xx on /health within the readiness window"
}

@test "print_failed_deployment_hints: enriches Unhealthy with HTTP statuscode detail and targeted fix" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"Unhealthy","lastTimestamp":"2026-05-20T13:13:42Z","message":"Startup probe failed: HTTP probe failed with statuscode: 502"}]}'

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"api","state":{"waiting":{"reason":"Unhealthy"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Detected: Startup probe"
  assert_contains "$output" "HTTP 502"
  # SUGGESTED_FIX cites the status code and points to app logs
  assert_contains "$output" "responded with HTTP 502"
  assert_contains "$output" "inspect application logs"
}

@test "print_failed_deployment_hints: enriches Unhealthy with timeout detail and targeted fix" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"Unhealthy","lastTimestamp":"2026-05-20T13:13:42Z","message":"Startup probe failed: Get \"http://10.0.0.1:8080/health\": context deadline exceeded (Client.Timeout exceeded while awaiting headers)"}]}'

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"api","state":{"waiting":{"reason":"Unhealthy"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Detected: Startup probe"
  assert_contains "$output" "timed out"
  # SUGGESTED_FIX mentions timing knobs
  assert_contains "$output" "initialDelaySeconds"
}

@test "print_failed_deployment_hints: Unhealthy picks the latest event when multiple are present" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"
  # Two Warnings: an older 502 and a newer connection-refused. The fix must reflect the newer one.
  export ALL_EVENTS='{"items":[
    {"type":"Warning","reason":"Unhealthy","lastTimestamp":"2026-05-20T13:10:00Z","message":"Startup probe failed: HTTP probe failed with statuscode: 502"},
    {"type":"Warning","reason":"Unhealthy","lastTimestamp":"2026-05-20T13:13:42Z","message":"Startup probe failed: Get \"http://10.0.0.1:8080/health\": dial tcp: connect: connection refused"}
  ]}'

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"api","state":{"waiting":{"reason":"Unhealthy"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  # Latest event wins → connection-refused remediation, not the older HTTP 502 one
  assert_contains "$output" "not listening on port 8080"
  assert_not_contains "$output" "responded with HTTP 502"
}

# =============================================================================
# CONTEXT fallback handling
# =============================================================================
@test "print_failed_deployment_hints: OOMKilled without ram_memory does not leave dangling (Mi)" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"
  # CONTEXT present but no ram_memory capability — plausible if the scope did not define memory.
  export CONTEXT='{"scope":{"name":"my-app","dimensions":"prod","capabilities":{"health_check":{"path":"/health"}}}}'

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"app","lastState":{"terminated":{"reason":"OOMKilled","exitCode":137}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "exceeded its memory limit"
  # The (Mi) parenthetical must not appear empty when ram_memory is missing.
  assert_not_contains "$output" "(Mi)"
}

@test "print_failed_deployment_hints: applies CONTEXT defaults gracefully when CONTEXT is unset" {
  # Drop the bats-provided CONTEXT so we exercise the ${CONTEXT:-{}} fallback.
  unset CONTEXT
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"api","state":{"waiting":{"reason":"Unhealthy"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  # health_check_path default "/" must apply when CONTEXT is unset.
  assert_contains "$output" "health check at /."
  assert_contains "$output" "returns 2xx on /"
  # Guard against the previous escape bug: a literal backslash in the message
  # would indicate jq received {\} instead of {} and silently failed.
  assert_not_contains "$output" "{\\"
}

# =============================================================================
# Unknown Reason → falls through to generic checklist
# =============================================================================
@test "print_failed_deployment_hints: unknown reason still prints generic hints alongside specific reason" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"app","state":{"waiting":{"reason":"WeirdNewError"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: Pods are failing with reason: WeirdNewError"
  assert_contains "$output" "📋 Detected: WeirdNewError on container app"
  # No suggested fix → fall through to generic checklist.
  assert_not_contains "$output" "💡 Suggested fix:"
  assert_contains "$output" "⚠️  Application Startup Issue Detected"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# Event-derived Diagnostics (no pods to inspect)
# =============================================================================
@test "print_failed_deployment_hints: derives FailedScheduling from ALL_EVENTS when pods unavailable" {
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"FailedScheduling"},{"type":"Warning","reason":"FailedScheduling"}]}'

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Reason: No node has enough resources"
  assert_contains "$output" "📋 Detected: FailedScheduling"
  assert_contains "$output" "💡 Suggested fix: Reduce requested resources"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: shows top warning event reasons summary" {
  export ALL_EVENTS='{"items":[
    {"type":"Warning","reason":"BackOff"},
    {"type":"Warning","reason":"BackOff"},
    {"type":"Warning","reason":"BackOff"},
    {"type":"Warning","reason":"FailedMount"},
    {"type":"Warning","reason":"FailedMount"},
    {"type":"Warning","reason":"Unhealthy"},
    {"type":"Normal","reason":"Pulled"}
  ]}'

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Recent warnings:"
  assert_contains "$output" "BackOff (×3)"
  assert_contains "$output" "FailedMount (×2)"
  assert_contains "$output" "Unhealthy (×1)"
  # Normal events should not be summarized
  assert_not_contains "$output" "Pulled (×"
}

# =============================================================================
# Replica progress reporting
# =============================================================================
@test "print_failed_deployment_hints: includes replica progress when desired/ready/current are set" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"
  export desired=3 ready=1 current=2

  kubectl() {
    case "$*" in
      "get pods"*)
        echo '{"items":[{"status":{"containerStatuses":[{"name":"app","state":{"waiting":{"reason":"CrashLoopBackOff"}}}]}}]}'
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📊 Progress at failure: 1/3 ready, 2/3 available"
}
