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
  local expected
  expected=$(cat <<'EOF'

⚠️  Application Startup Issue Detected

💡 Possible causes:
   Your application was unable to start within the expected timeframe

🔧 How to fix:
   1. Port Configuration: Ensure your application listens on port 8080
   2. Health Check Endpoint: Verify your app responds to: /health
   3. Application Logs: Review logs for startup errors (database connections,
      missing dependencies, or initialization errors)
   4. Memory Allocation: Current allocation is 512Mi - increase if needed
   5. Environment Variables: Verify all required variables are configured in
      parameters for scope 'my-app' or dimensions: production
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The container exceeded its memory limit (512Mi) and was terminated.
📋 Detected: OOMKilled on container app (exit 137)
📋 Details: out of memory
💡 Suggested fix: Increase ram_memory for scope 'my-app' or reduce application memory usage.
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The container image could not be pulled.
📋 Detected: ImagePullBackOff on container web
📋 Details: manifest unknown
💡 Suggested fix: Verify the image name, tag, and registry credentials are correct.
EOF
)
  assert_equal "$output" "$expected"
  assert_not_contains "$output" "exit "
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The container started and crashed repeatedly.
📋 Detected: CrashLoopBackOff on container worker
📋 Details: back-off 5m0s restarting failed container
💡 Suggested fix: Review application logs for startup errors (failed dependencies, bad config, panics).
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The container configuration is invalid.
📋 Detected: CreateContainerConfigError on container api
📋 Details: secret "db-creds" not found
💡 Suggested fix: Check for missing secrets or configmaps referenced by the deployment.
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The container failed to run its entrypoint.
📋 Detected: RunContainerError on container app
💡 Suggested fix: Verify the start command and that required binaries exist in the image.
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The startup binary is missing or not executable inside the image.
📋 Detected: ContainerCannotRun on container app (exit 127)
📋 Details: exec: "/app": no such file
💡 Suggested fix: Rebuild the image ensuring the entrypoint exists and has execute permissions.
EOF
)
  assert_equal "$output" "$expected"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies FailedMount from ALL_EVENTS" {
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"FailedMount","message":"MountVolume.SetUp failed"}]}'

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<'EOF'

📋 Reason: A volume could not be mounted onto the pod.
📋 Detected: FailedMount
📋 Recent warnings:
  • FailedMount (×1)
💡 Suggested fix: Check that the referenced PVC, secret, or configmap exists and is accessible.
EOF
)
  assert_equal "$output" "$expected"
  assert_not_contains "$output" "⚠️  Application Startup Issue Detected"
}

@test "print_failed_deployment_hints: identifies FailedCreatePodSandBox from ALL_EVENTS" {
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"FailedCreatePodSandBox","message":"failed to create pod sandbox"}]}'

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<'EOF'

📋 Reason: Kubernetes could not create the pod sandbox.
📋 Detected: FailedCreatePodSandBox
📋 Recent warnings:
  • FailedCreatePodSandBox (×1)
💡 Suggested fix: Check node health, CNI configuration, and pod security policies.
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The application did not pass its health check at /health.
📋 Detected: Unhealthy on container api
💡 Suggested fix: Ensure the app listens on port 8080 and returns 2xx on /health within the readiness window.
EOF
)
  assert_equal "$output" "$expected"
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
  # HUMAN_MESSAGE retains the base sentence and appends the translated probe failure;
  # SUGGESTED_FIX is targeted: tells the user the app is not binding the port.
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The application did not pass its health check at /health. Detected: Startup probe — app is not yet listening on /health.
📋 Detected: Unhealthy on container api
📋 Recent warnings:
  • Unhealthy (×1)
💡 Suggested fix: The container is not listening on port 8080 — verify the start command runs, the process binds to 0.0.0.0:8080, and nothing is crashing before it accepts connections.
EOF
)
  assert_equal "$output" "$expected"
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
  # SUGGESTED_FIX cites the status code and points to app logs
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The application did not pass its health check at /health. Detected: Startup probe — app responded with HTTP 502 (expected 2xx).
📋 Detected: Unhealthy on container api
📋 Recent warnings:
  • Unhealthy (×1)
💡 Suggested fix: The app responded with HTTP 502 on /health — inspect application logs for startup errors; the process is running but /health is not returning 2xx.
EOF
)
  assert_equal "$output" "$expected"
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
  # SUGGESTED_FIX mentions timing knobs
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The application did not pass its health check at /health. Detected: Startup probe — request timed out on /health.
📋 Detected: Unhealthy on container api
📋 Recent warnings:
  • Unhealthy (×1)
💡 Suggested fix: The probe timed out — the app may be slow to start or /health is blocking. Consider increasing startup probe initialDelaySeconds/timeoutSeconds, or making /health lighter.
EOF
)
  assert_equal "$output" "$expected"
}

@test "print_failed_deployment_hints: falls back to raw Unhealthy message when translation is impossible" {
  export K8S_NAMESPACE="ns" DEPLOYMENT_ID="d1"
  # Message does not match any known probe pattern → translate_probe_message returns non-zero.
  # The raw text must still be surfaced in the hint instead of being silently dropped.
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"Unhealthy","lastTimestamp":"2026-05-20T13:13:42Z","message":"completely unknown probe failure format from a future K8s"}]}'

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
  # Raw message appears verbatim, appended to the base sentence
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The application did not pass its health check at /health. Detected: completely unknown probe failure format from a future K8s
📋 Detected: Unhealthy on container api
📋 Recent warnings:
  • Unhealthy (×1)
💡 Suggested fix: Ensure the app listens on port 8080 and returns 2xx on /health within the readiness window.
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The application did not pass its health check at /health. Detected: Startup probe — app is not yet listening on /health.
📋 Detected: Unhealthy on container api
📋 Recent warnings:
  • Unhealthy (×2)
💡 Suggested fix: The container is not listening on port 8080 — verify the start command runs, the process binds to 0.0.0.0:8080, and nothing is crashing before it accepts connections.
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The container exceeded its memory limit and was terminated.
📋 Detected: OOMKilled on container app (exit 137)
💡 Suggested fix: Increase ram_memory for scope 'my-app' or reduce application memory usage.
EOF
)
  assert_equal "$output" "$expected"
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
  # health_check_path default "/" applies when CONTEXT is unset.
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The application did not pass its health check at /.
📋 Detected: Unhealthy on container api
💡 Suggested fix: Ensure the app listens on port 8080 and returns 2xx on / within the readiness window.
EOF
)
  assert_equal "$output" "$expected"
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
  # No suggested fix → fall through to generic checklist, printed alongside the specific reason.
  local expected
  expected=$(cat <<'EOF'

📋 Reason: Pods are failing with reason: WeirdNewError
📋 Detected: WeirdNewError on container app

⚠️  Application Startup Issue Detected

💡 Possible causes:
   Your application was unable to start within the expected timeframe

🔧 How to fix:
   1. Port Configuration: Ensure your application listens on port 8080
   2. Health Check Endpoint: Verify your app responds to: /health
   3. Application Logs: Review logs for startup errors (database connections,
      missing dependencies, or initialization errors)
   4. Memory Allocation: Current allocation is 512Mi - increase if needed
   5. Environment Variables: Verify all required variables are configured in
      parameters for scope 'my-app' or dimensions: production
EOF
)
  assert_equal "$output" "$expected"
  # No suggested fix → fall through to generic checklist.
  assert_not_contains "$output" "💡 Suggested fix:"
}

# =============================================================================
# Event-derived Diagnostics (no pods to inspect)
# =============================================================================
@test "print_failed_deployment_hints: derives FailedScheduling from ALL_EVENTS when pods unavailable" {
  export ALL_EVENTS='{"items":[{"type":"Warning","reason":"FailedScheduling"},{"type":"Warning","reason":"FailedScheduling"}]}'

  run bash "$BATS_TEST_DIRNAME/../print_failed_deployment_hints"

  [ "$status" -eq 0 ]
  # A lone apostrophe ("pod's") inside a heredoc nested in $(...) trips a bash
  # command-substitution parsing quirk, so this one assertion is built with
  # `read` instead of `cat` to sidestep it.
  local expected
  IFS= read -r -d '' expected <<'EOF' || true

📋 Reason: No node has enough resources or matches the pod's scheduling constraints.
📋 Detected: FailedScheduling
📋 Recent warnings:
  • FailedScheduling (×2)
💡 Suggested fix: Reduce requested resources, free cluster capacity, or review nodeSelector/affinity rules.
EOF
  expected="${expected%$'\n'}"
  assert_equal "$output" "$expected"
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
  # Normal events are not summarized; only the top 3 Warning reasons appear, most frequent first.
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The container started and crashed repeatedly.
📋 Detected: BackOff
📋 Recent warnings:
  • BackOff (×3)
  • FailedMount (×2)
  • Unhealthy (×1)
💡 Suggested fix: Review application logs for startup errors (failed dependencies, bad config, panics).
EOF
)
  assert_equal "$output" "$expected"
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
  local expected
  expected=$(cat <<'EOF'

📋 Reason: The container started and crashed repeatedly.
📋 Detected: CrashLoopBackOff on container app
📊 Progress at failure: 1/3 ready, 2/3 available
💡 Suggested fix: Review application logs for startup errors (failed dependencies, bad config, panics).
EOF
)
  assert_equal "$output" "$expected"
}
