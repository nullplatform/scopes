#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/networking/gateway/cleanup_service_to_service
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SCRIPT="$PROJECT_ROOT/k8s/deployment/networking/gateway/cleanup_service_to_service"
  export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  export EXISTING_FIXTURE=""
  export LIST_FAILS=""
  export DELETE_FAILS=""

  export CONTEXT='{
    "k8s_namespace": "apps",
    "scope": {"id": 123},
    "names": {"stable_service": "checkout-api-production"},
    "service_to_service": {"enabled": true, "ports": [8080, 8081]}
  }'

  kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    case "$1" in
      get)
        [ -n "$LIST_FAILS" ] && { echo "Error from server (Forbidden): httproutes is forbidden"; return 1; }
        [ -n "$EXISTING_FIXTURE" ] && printf '%s\n' $EXISTING_FIXTURE
        return 0 ;;
      delete)
        [ -n "$DELETE_FAILS" ] && { echo "Error from server (Forbidden): cannot delete"; return 1; }
        shift
        local object
        for object in "$@"; do
          case "$object" in
            service/*) echo "service \"${object#*/}\" deleted" ;;
            httproute/*) echo "httproute.gateway.networking.k8s.io \"${object#*/}\" deleted" ;;
          esac
        done ;;
    esac
  }
  export -f kubectl

  for helper in np_scope_step_begin np_scope_step_end np_scope_failure np_scope_k8s_deleted; do
    eval "$helper() { :; }"
    export -f "$helper"
  done
}

mock_tracing() {
  export TRACE_LOG="$BATS_TEST_TMPDIR/trace.log"
  for helper in np_scope_step_begin np_scope_step_end np_scope_failure np_scope_k8s_deleted; do
    eval "$helper() { echo \"$helper \$*\" >> \"\$TRACE_LOG\"; }"
    export -f "$helper"
  done
}

@test "cleanup_service_to_service: lists the scope's objects by label and deletes nothing when they are all rendered" {
  export EXISTING_FIXTURE="Service/checkout-api-production HTTPRoute/checkout-api-production-http-8080 HTTPRoute/checkout-api-production-http-8081"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_equal "$(cat "$KUBECTL_LOG")" 'get service,httproute -n apps -l nullplatform.io/stable-service=true,scope_id=123 -o jsonpath={range .items[*]}{.kind}/{.metadata.name}{"\n"}{end}'
  assert_equal "$output" ""
}

@test "cleanup_service_to_service: does nothing when the scope never had the objects" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.service_to_service)')

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  [[ "$(cat "$KUBECTL_LOG")" != *"delete"* ]] || false
}

@test "cleanup_service_to_service: deletes every object once the feature is disabled" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.service_to_service)')
  export EXISTING_FIXTURE="Service/checkout-api-production HTTPRoute/checkout-api-production-http-8080"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_LOG")" "delete service/checkout-api-production httproute/checkout-api-production-http-8080 -n apps --ignore-not-found"
  assert_contains "$output" "✅ Removed stale service-to-service objects: service/checkout-api-production httproute/checkout-api-production-http-8080"
}

@test "cleanup_service_to_service: deletes only the route of a removed port" {
  export EXISTING_FIXTURE="Service/checkout-api-production HTTPRoute/checkout-api-production-http-8080 HTTPRoute/checkout-api-production-http-8081 HTTPRoute/checkout-api-production-http-9000"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_LOG")" "delete httproute/checkout-api-production-http-9000 -n apps --ignore-not-found"
}

@test "cleanup_service_to_service: keeps the grpc route of a GRPC port and deletes its old http route" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.service_to_service.ports += [9090] | .service_to_service.grpc_ports = [9090]')
  export EXISTING_FIXTURE="Service/checkout-api-production HTTPRoute/checkout-api-production-http-8080 HTTPRoute/checkout-api-production-http-8081 HTTPRoute/checkout-api-production-grpc-9090 HTTPRoute/checkout-api-production-http-9090"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_LOG")" "delete httproute/checkout-api-production-http-9090 -n apps --ignore-not-found"
  [[ "$(cat "$KUBECTL_LOG")" != *"grpc-9090 "* ]] || false
}

@test "cleanup_service_to_service: a failed listing only warns" {
  export LIST_FAILS=1

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  Could not list the scope's service-to-service objects, skipping their cleanup"
}

@test "cleanup_service_to_service: a failed delete fails the deployment with hints" {
  export EXISTING_FIXTURE="HTTPRoute/checkout-api-production-http-9000"
  export DELETE_FAILS=1

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Could not remove the stale service-to-service objects"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
}

@test "cleanup_service_to_service: traces the removal in its own step" {
  mock_tracing
  export EXISTING_FIXTURE="HTTPRoute/checkout-api-production-http-9000"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_equal "$(cat "$TRACE_LOG")" 'np_scope_step_begin remove-stale-service-to-service --title Remove stale service-to-service objects
np_scope_k8s_deleted apps httproute.gateway.networking.k8s.io "checkout-api-production-http-9000" deleted
np_scope_step_end 0'
}

@test "cleanup_service_to_service: opens no trace step when there is nothing to remove" {
  mock_tracing

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  [ ! -f "$TRACE_LOG" ]
}

@test "cleanup_service_to_service: a deployment delete removes every object, even with the feature enabled" {
  export EXISTING_FIXTURE="Service/checkout-api-production HTTPRoute/checkout-api-production-http-8080"
  export SERVICE_TO_SERVICE_REMOVE_ALL=true

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$KUBECTL_LOG")" "delete service/checkout-api-production httproute/checkout-api-production-http-8080 -n apps --ignore-not-found"
}

@test "cleanup_service_to_service: the delete workflow runs it in remove-all mode" {
  run yq -r '.steps[] | select(.file == "$SERVICE_PATH/deployment/networking/gateway/cleanup_service_to_service") | .configuration.SERVICE_TO_SERVICE_REMOVE_ALL' "$PROJECT_ROOT/k8s/deployment/workflows/delete.yaml"

  [ "$status" -eq 0 ]
  assert_equal "$output" "true"
}
