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
