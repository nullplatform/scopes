#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/verify_ingress_reconciliation - ingress verification
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export K8S_NAMESPACE="test-namespace"
  export SCOPE_ID="scope-123"
  export INGRESS_VISIBILITY="internet-facing"
  export REGION="us-east-1"
  export ALB_RECONCILIATION_ENABLED="false"
  export MAX_WAIT_SECONDS=1
  export CHECK_INTERVAL=0

  export CONTEXT='{
    "scope": {
      "slug": "my-app",
      "domain": "app.example.com",
      "domains": []
    },
    "alb_name": "k8s-test-alb",
    "deployment": {
      "strategy": "rolling"
    }
  }'
}

teardown() {
  unset CONTEXT
}

# =============================================================================
# Success Case
# =============================================================================
@test "verify_ingress_reconciliation: succeeds with correct logging" {
  run bash -c "
    kubectl() {
      case \"\$1\" in
        get)
          if [[ \"\$2\" == \"ingress\" ]]; then
            echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
            return 0
          elif [[ \"\$2\" == \"events\" ]]; then
            echo '{\"items\": [{\"type\": \"Normal\", \"reason\": \"SuccessfullyReconciled\", \"message\": \"Ingress reconciled\", \"involvedObject\": {\"resourceVersion\": \"12345\"}, \"lastTimestamp\": \"2024-01-01T00:00:00Z\"}]}'
            return 0
          fi
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL' CONTEXT='$CONTEXT'
    export ALB_RECONCILIATION_ENABLED='$ALB_RECONCILIATION_ENABLED' REGION='$REGION'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "📋 Ingress: k-8-s-my-app-scope-123-internet-facing | Namespace: test-namespace | Timeout: 1s"
  assert_contains "$output" "📋 ALB reconciliation disabled, checking cluster events only"
  assert_contains "$output" "✅ Ingress successfully reconciled"
}

@test "verify_ingress_reconciliation: skips for blue-green when ALB disabled" {
  local bg_context='{"scope":{"slug":"my-app","domain":"app.example.com"},"deployment":{"strategy":"blue_green"}}'

  run bash -c "
    kubectl() { return 0; }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL'
    export ALB_RECONCILIATION_ENABLED='false' REGION='$REGION'
    export CONTEXT='$bg_context'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "⚠️ Skipping ALB verification (ALB access needed for blue-green traffic validation)"
}

# =============================================================================
# Error Cases
# =============================================================================
@test "verify_ingress_reconciliation: fails with full troubleshooting on certificate error" {
  run bash -c "
    kubectl() {
      case \"\$1\" in
        get)
          if [[ \"\$2\" == \"ingress\" ]]; then
            echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
            return 0
          elif [[ \"\$2\" == \"events\" ]]; then
            echo '{\"items\": [{\"type\": \"Warning\", \"reason\": \"CertificateError\", \"message\": \"no certificate found for host app.example.com\", \"involvedObject\": {\"resourceVersion\": \"12345\"}, \"lastTimestamp\": \"2024-01-01T00:00:00Z\"}]}'
            return 0
          fi
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL' CONTEXT='$CONTEXT'
    export ALB_RECONCILIATION_ENABLED='$ALB_RECONCILIATION_ENABLED' REGION='$REGION'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Certificate error detected"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Ingress hostname does not match any SSL/TLS certificate in ACM"
  assert_contains "$output" "- Certificate does not cover the hostname (check wildcards)"
  assert_contains "$output" "- Message: no certificate found for host app.example.com"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Verify hostname matches certificate in ACM"
  assert_contains "$output" "- Ensure certificate includes exact hostname or matching wildcard"
}

@test "verify_ingress_reconciliation: fails with full troubleshooting when ingress not found" {
  run bash -c "
    kubectl() {
      case \"\$1\" in
        get)
          if [[ \"\$2\" == \"ingress\" ]]; then
            return 1
          fi
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL' CONTEXT='$CONTEXT'
    export ALB_RECONCILIATION_ENABLED='$ALB_RECONCILIATION_ENABLED' REGION='$REGION'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to get ingress k-8-s-my-app-scope-123-internet-facing"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- Ingress does not exist yet"
  assert_contains "$output" "- Namespace test-namespace is incorrect"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- List ingresses: kubectl get ingress -n test-namespace"
}

@test "verify_ingress_reconciliation: fails when ALB not found" {
  run bash -c "
    kubectl() {
      echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
      return 0
    }
    aws() {
      echo 'An error occurred (LoadBalancerNotFound)'
      return 1
    }
    export -f kubectl aws
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL' CONTEXT='$CONTEXT'
    export ALB_RECONCILIATION_ENABLED='true' REGION='$REGION'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "📋 ALB validation enabled: k8s-test-alb for domain app.example.com"
  assert_contains "$output" "⚠️  Could not find ALB: k8s-test-alb"
}

@test "verify_ingress_reconciliation: fails when cannot get ALB listeners" {
  run bash -c "
    kubectl() {
      echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
      return 0
    }
    aws() {
      case \"\$1\" in
        elbv2)
          case \"\$2\" in
            describe-load-balancers)
              echo 'arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/test-alb/abc123'
              return 0
              ;;
            describe-listeners)
              echo 'AccessDenied: User is not authorized'
              return 1
              ;;
          esac
          ;;
      esac
      return 0
    }
    export -f kubectl aws
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='1' CHECK_INTERVAL='1' CONTEXT='$CONTEXT'
    export ALB_RECONCILIATION_ENABLED='true' REGION='$REGION'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "📋 ALB validation enabled: k8s-test-alb for domain app.example.com"
  assert_contains "$output" "⚠️  Could not get listeners for ALB"
}

@test "verify_ingress_reconciliation: detects weights mismatch" {
  local weights_context='{"scope":{"slug":"my-app","domain":"app.example.com","current_active_deployment":"deploy-old"},"alb_name":"k8s-test-alb","deployment":{"strategy":"rolling","strategy_data":{"desired_switched_traffic":50}}}'

  run bash -c "
    kubectl() {
      echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
      return 0
    }
    aws() {
      case \"\$2\" in
        describe-load-balancers)
          echo 'arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/test-alb/abc123'
          ;;
        describe-listeners)
          echo '{\"Listeners\":[{\"ListenerArn\":\"arn:aws:listener/123\"}]}'
          ;;
        describe-rules)
          echo '{\"Rules\":[{\"Conditions\":[{\"Field\":\"host-header\",\"Values\":[\"app.example.com\"]}],\"Actions\":[{\"Type\":\"forward\",\"ForwardConfig\":{\"TargetGroups\":[{\"Weight\":80},{\"Weight\":20}]}}]}]}'
          ;;
      esac
      return 0
    }
    export -f kubectl aws
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='1' CHECK_INTERVAL='1'
    export ALB_RECONCILIATION_ENABLED='true' VERIFY_WEIGHTS='true' REGION='$REGION'
    export CONTEXT='$weights_context'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "📋 ALB validation enabled: k8s-test-alb for domain app.example.com"
  assert_contains "$output" "📝 Checking domain: app.example.com"
  assert_contains "$output" "✅ Found rule for domain: app.example.com"
  assert_contains "$output" "❌ Weights mismatch: expected="
}

@test "verify_ingress_reconciliation: detects domain not found in ALB rules" {
  run bash -c "
    kubectl() {
      echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
      return 0
    }
    aws() {
      case \"\$2\" in
        describe-load-balancers)
          echo 'arn:aws:elasticloadbalancing:us-east-1:123456789:loadbalancer/app/test-alb/abc123'
          ;;
        describe-listeners)
          echo '{\"Listeners\":[{\"ListenerArn\":\"arn:aws:listener/123\"}]}'
          ;;
        describe-rules)
          echo '{\"Rules\":[{\"Conditions\":[{\"Field\":\"host-header\",\"Values\":[\"other-domain.com\"]}]}]}'
          ;;
      esac
      return 0
    }
    export -f kubectl aws
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='1' CHECK_INTERVAL='1' CONTEXT='$CONTEXT'
    export ALB_RECONCILIATION_ENABLED='true' REGION='$REGION'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "📋 ALB validation enabled: k8s-test-alb for domain app.example.com"
  assert_contains "$output" "📝 Checking domain: app.example.com"
  assert_contains "$output" "❌ Domain not found in ALB rules: app.example.com"
  assert_contains "$output" "⚠️  Some domains missing from ALB configuration"
}

@test "verify_ingress_reconciliation: fails with full troubleshooting on timeout" {
  run bash -c "
    kubectl() {
      case \"\$2\" in
        ingress)
          echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
          ;;
        events)
          echo '{\"items\": []}'
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='1' CHECK_INTERVAL='1' CONTEXT='$CONTEXT'
    export ALB_RECONCILIATION_ENABLED='false' REGION='$REGION'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Timeout waiting for ingress reconciliation after 1s"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "- ALB Ingress Controller not running or unhealthy"
  assert_contains "$output" "- Network connectivity issues"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Check controller: kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
  assert_contains "$output" "- Check ingress: kubectl describe ingress k-8-s-my-app-scope-123-internet-facing -n test-namespace"
  assert_contains "$output" "📋 Recent events:"
}

@test "verify_ingress_reconciliation: fails on Error event type with error messages" {
  run bash -c "
    kubectl() {
      case \"\$2\" in
        ingress)
          echo '{\"metadata\": {\"resourceVersion\": \"12345\"}}'
          ;;
        events)
          echo '{\"items\": [{\"type\": \"Error\", \"reason\": \"SyncFailed\", \"message\": \"Failed to sync ALB\", \"involvedObject\": {\"resourceVersion\": \"12345\"}, \"lastTimestamp\": \"2024-01-01T00:00:00Z\"}]}'
          ;;
      esac
      return 0
    }
    export -f kubectl
    export K8S_NAMESPACE='$K8S_NAMESPACE' SCOPE_ID='$SCOPE_ID' INGRESS_VISIBILITY='$INGRESS_VISIBILITY'
    export MAX_WAIT_SECONDS='$MAX_WAIT_SECONDS' CHECK_INTERVAL='$CHECK_INTERVAL' CONTEXT='$CONTEXT'
    export ALB_RECONCILIATION_ENABLED='false' REGION='$REGION'
    source '$BATS_TEST_DIRNAME/../verify_ingress_reconciliation'
  "

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Verifying ingress reconciliation..."
  assert_contains "$output" "📋 ALB reconciliation disabled, checking cluster events only"
  assert_contains "$output" "❌ Ingress reconciliation failed"
  assert_contains "$output" "💡 Error messages:"
  assert_contains "$output" "- Failed to sync ALB"
}
