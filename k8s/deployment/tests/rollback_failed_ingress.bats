#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/rollback_failed_ingress - ingress rollback on failure
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"
  export INGRESS_VISIBILITY="internet-facing"
  export DNS_TYPE="route53"
  export ALB_ROLLBACK_ON_RECONCILIATION_FAILURE="true"

  export CONTEXT='{
    "scope": {
      "slug": "my-app"
    },
    "alb_name": "k8s-test-alb"
  }'
}

teardown() {
  unset CONTEXT
}

# =============================================================================
# Success Cases
# =============================================================================
@test "rollback_failed_ingress: deletes main ingress" {
  run bash -c "
    DELETED_INGRESSES=()
    kubectl() {
      case \"\$1\" in
        delete)
          DELETED_INGRESSES+=(\"\$3\")
          return 0
          ;;
        get)
          echo ''
          return 0
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export DNS_TYPE='$DNS_TYPE' ALB_ROLLBACK_ON_RECONCILIATION_FAILURE='$ALB_ROLLBACK_ON_RECONCILIATION_FAILURE'
    export CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../rollback_failed_ingress'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "Rolling back ingress"
  assert_contains "$output" "k-8-s-my-app-scope-123-internet-facing"
  assert_contains "$output" "Deleted ingress"
  assert_contains "$output" "Rollback complete"
}

@test "rollback_failed_ingress: deletes additional port ingresses" {
  run bash -c "
    kubectl() {
      case \"\$1\" in
        delete)
          echo \"deleted \$3\"
          return 0
          ;;
        get)
          if [[ \"\$*\" == *\"-l\"* ]]; then
            echo 'k-8-s-my-app-scope-123-http-8081-internet-facing k-8-s-my-app-scope-123-grpc-9090-internet-facing'
            return 0
          fi
          echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
          return 0
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export DNS_TYPE='$DNS_TYPE' ALB_ROLLBACK_ON_RECONCILIATION_FAILURE='$ALB_ROLLBACK_ON_RECONCILIATION_FAILURE'
    export CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../rollback_failed_ingress'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "Deleted ingress: k-8-s-my-app-scope-123-internet-facing"
  assert_contains "$output" "Deleted additional port ingress: k-8-s-my-app-scope-123-http-8081-internet-facing"
  assert_contains "$output" "Deleted additional port ingress: k-8-s-my-app-scope-123-grpc-9090-internet-facing"
}

# =============================================================================
# Skip Cases
# =============================================================================
@test "rollback_failed_ingress: skips when disabled" {
  run bash -c "
    kubectl() { echo 'should not be called'; return 1; }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export DNS_TYPE='$DNS_TYPE' ALB_ROLLBACK_ON_RECONCILIATION_FAILURE='false'
    export CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../rollback_failed_ingress'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "Ingress rollback disabled"
  [[ "$output" != *"Rolling back ingress"* ]]
}

@test "rollback_failed_ingress: skips for non-route53 DNS types" {
  run bash -c "
    kubectl() { echo 'should not be called'; return 1; }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export DNS_TYPE='azure' ALB_ROLLBACK_ON_RECONCILIATION_FAILURE='true'
    export CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../rollback_failed_ingress'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "ingress rollback only applies to route53"
  [[ "$output" != *"Rolling back ingress"* ]]
}

@test "rollback_failed_ingress: skips for external_dns DNS type" {
  run bash -c "
    kubectl() { echo 'should not be called'; return 1; }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export DNS_TYPE='external_dns' ALB_ROLLBACK_ON_RECONCILIATION_FAILURE='true'
    export CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../rollback_failed_ingress'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "ingress rollback only applies to route53"
}

# =============================================================================
# Resilience Cases
# =============================================================================
@test "rollback_failed_ingress: handles missing ingress gracefully" {
  run bash -c "
    kubectl() {
      case \"\$1\" in
        delete)
          return 0
          ;;
        get)
          echo ''
          return 0
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export DNS_TYPE='$DNS_TYPE' ALB_ROLLBACK_ON_RECONCILIATION_FAILURE='$ALB_ROLLBACK_ON_RECONCILIATION_FAILURE'
    export CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../rollback_failed_ingress'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "Rollback complete"
}

@test "rollback_failed_ingress: continues when kubectl delete fails" {
  run bash -c "
    kubectl() {
      case \"\$1\" in
        delete)
          return 1
          ;;
        get)
          echo 'extra-ingress'
          return 0
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export DNS_TYPE='$DNS_TYPE' ALB_ROLLBACK_ON_RECONCILIATION_FAILURE='$ALB_ROLLBACK_ON_RECONCILIATION_FAILURE'
    export CONTEXT='$CONTEXT'
    source '$BATS_TEST_DIRNAME/../rollback_failed_ingress'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "Could not delete ingress"
  assert_contains "$output" "Rollback complete"
}
