#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/wait_on_balancer - wait for DNS/balancer setup
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  # Default environment
  export K8S_NAMESPACE="default-namespace"
  export DNS_TYPE="external_dns"

  # Base CONTEXT with required fields
  export CONTEXT='{
    "scope": {
      "id": "scope-123",
      "slug": "my-scope",
      "domain": "my-scope.example.com"
    },
    "application": {
      "slug": "my-app"
    }
  }'

  # Mock sleep to be instant
  sleep() {
    return 0
  }
  export -f sleep

  # Mock kubectl: DNSEndpoint found with observedGeneration=1 by default
  kubectl() {
    case "$*" in
      "get dnsendpoint k8s-my-app-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status.observedGeneration}")
        echo "1"
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl
}

teardown() {
  unset -f kubectl
  unset -f sleep
}

# =============================================================================
# external_dns: Success on first attempt
# =============================================================================
@test "wait_on_balancer: external_dns success on first attempt" {
  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Waiting for balancer/DNS setup to complete..."
  assert_contains "$output" "📋 Checking ExternalDNS record creation for domain: my-scope.example.com"
  assert_contains "$output" "🔍 Checking DNSEndpoint status: k8s-my-app-my-scope-scope-123-dns (attempt 1/"
  assert_contains "$output" "✅ DNSEndpoint k8s-my-app-my-scope-scope-123-dns processed by ExternalDNS (observedGeneration=1)"
  assert_contains "$output" "✨ ExternalDNS setup completed successfully"
}

# =============================================================================
# external_dns: Success after retries
# =============================================================================
@test "wait_on_balancer: external_dns success after retries" {
  export KUBECTL_CALL_COUNT_FILE="$BATS_TEST_TMPDIR/kubectl-call-count"
  echo 0 > "$KUBECTL_CALL_COUNT_FILE"

  kubectl() {
    local call_count
    call_count="$(cat "$KUBECTL_CALL_COUNT_FILE")"
    call_count=$((call_count + 1))
    echo "$call_count" > "$KUBECTL_CALL_COUNT_FILE"

    case "$*" in
      "get dnsendpoint k8s-my-app-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status.observedGeneration}")
        if [ "$call_count" -ge 2 ]; then
          echo "1"
          return 0
        fi
        echo ""
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking DNSEndpoint status: k8s-my-app-my-scope-scope-123-dns (attempt 1/"
  assert_contains "$output" "📋 DNSEndpoint not yet processed, waiting 10s..."
  assert_contains "$output" "🔍 Checking DNSEndpoint status: k8s-my-app-my-scope-scope-123-dns (attempt 2/"
  assert_contains "$output" "✅ DNSEndpoint k8s-my-app-my-scope-scope-123-dns processed by ExternalDNS (observedGeneration=1)"
  assert_contains "$output" "✨ ExternalDNS setup completed successfully"
}

# =============================================================================
# external_dns: Timeout after MAX_ITERATIONS
# =============================================================================
@test "wait_on_balancer: external_dns timeout after MAX_ITERATIONS" {
  export MAX_ITERATIONS=2

  kubectl() {
    echo ""
    return 0
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ DNSEndpoint processing timeout after 20s"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "ExternalDNS may still be processing the DNSEndpoint resource"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check DNSEndpoint resources: kubectl get dnsendpoint -A"
  assert_contains "$output" "• Check ExternalDNS logs: kubectl logs -n external-dns -l app=external-dns --tail=50"
}

# =============================================================================
# external_dns: DNSEndpoint not found - keeps trying until timeout
# =============================================================================
@test "wait_on_balancer: external_dns DNS endpoint not found keeps retrying until timeout" {
  export MAX_ITERATIONS=2

  kubectl() {
    return 1
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 1 ]
  assert_contains "$output" "🔍 Checking DNSEndpoint status: k8s-my-app-my-scope-scope-123-dns"
  assert_contains "$output" "📋 DNSEndpoint not yet processed, waiting 10s..."
  assert_contains "$output" "❌ DNSEndpoint processing timeout after 20s"
}

# =============================================================================
# external_dns: APP_SLUG truncated to 20 chars in endpoint name
# =============================================================================
@test "wait_on_balancer: external_dns truncates APP_SLUG to 20 chars in endpoint name" {
  export CONTEXT='{
    "scope": {
      "id": "123",
      "slug": "qa",
      "domain": "qa.example.com"
    },
    "application": {
      "slug": "very-long-application-name-that-exceeds-limit"
    }
  }'

  kubectl() {
    case "$*" in
      "get dnsendpoint k8s-very-long-applicatio-qa-123-dns -n default-namespace -o jsonpath={.status.observedGeneration}")
        echo "1"
        return 0
        ;;
      *)
        echo ""
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "k8s-very-long-applicatio-qa-123-dns"
  assert_contains "$output" "✨ ExternalDNS setup completed successfully"
}

# =============================================================================
# route53: Skips check
# =============================================================================
@test "wait_on_balancer: route53 skips check" {
  export DNS_TYPE="route53"

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Waiting for balancer/DNS setup to complete..."
  assert_contains "$output" "📋 DNS Type route53 - DNS should already be configured"
  assert_contains "$output" "📋 Skipping DNS wait check"
}

# =============================================================================
# azure: Skips check
# =============================================================================
@test "wait_on_balancer: azure skips check" {
  export DNS_TYPE="azure"

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Waiting for balancer/DNS setup to complete..."
  assert_contains "$output" "📋 DNS Type azure - DNS should already be configured"
  assert_contains "$output" "📋 Skipping DNS wait check"
}

# =============================================================================
# Unknown DNS type: Skips
# =============================================================================
@test "wait_on_balancer: unknown DNS type skips" {
  export DNS_TYPE="cloudflare"

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Waiting for balancer/DNS setup to complete..."
  assert_contains "$output" "📋 Unknown DNS type: cloudflare"
  assert_contains "$output" "📋 Skipping DNS wait check"
}
