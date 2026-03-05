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
    }
  }'

  # Mock sleep to be instant
  sleep() {
    return 0
  }
  export -f sleep

  # Mock kubectl: DNS endpoint found with status by default
  kubectl() {
    case "$*" in
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status}")
        echo '{"observedGeneration":1}'
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f kubectl

  # Mock nslookup: resolves on first attempt by default
  nslookup() {
    case "$1" in
      "my-scope.example.com")
        if [ "$2" = "8.8.8.8" ]; then
          echo "Server:  8.8.8.8"
          echo "Address: 8.8.8.8#53"
          echo ""
          echo "Name:    my-scope.example.com"
          echo "Address: 10.0.0.1"
          return 0
        fi
        ;;
    esac
    return 1
  }
  export -f nslookup
}

teardown() {
  unset -f kubectl
  unset -f nslookup
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
  assert_contains "$output" "🔍 Checking DNS resolution for my-scope.example.com (attempt 1/"
  assert_contains "$output" "📋 Checking DNSEndpoint status: k-8-s-my-scope-scope-123-dns"
  assert_contains "$output" "📋 DNSEndpoint status:"
  assert_contains "$output" "✅ DNS record for my-scope.example.com is now resolvable"
  assert_contains "$output" "✅ Domain my-scope.example.com resolves to:"
  assert_contains "$output" "✨ ExternalDNS setup completed successfully"
}

# =============================================================================
# external_dns: Success after retries
# =============================================================================
@test "wait_on_balancer: external_dns success after retries" {
  local attempt=0
  nslookup() {
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 2 ] && [ "$1" = "my-scope.example.com" ] && [ "$2" = "8.8.8.8" ]; then
      echo "Server:  8.8.8.8"
      echo "Address: 8.8.8.8#53"
      echo ""
      echo "Name:    my-scope.example.com"
      echo "Address: 10.0.0.1"
      return 0
    fi
    return 1
  }
  export -f nslookup

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking DNS resolution for my-scope.example.com (attempt 1/"
  assert_contains "$output" "📋 DNS record not yet available, waiting 10s..."
  assert_contains "$output" "🔍 Checking DNS resolution for my-scope.example.com (attempt 2/"
  assert_contains "$output" "✅ DNS record for my-scope.example.com is now resolvable"
  assert_contains "$output" "✨ ExternalDNS setup completed successfully"
}

# =============================================================================
# external_dns: Timeout after MAX_ITERATIONS
# =============================================================================
@test "wait_on_balancer: external_dns timeout after MAX_ITERATIONS" {
  export MAX_ITERATIONS=2

  nslookup() {
    return 1
  }
  export -f nslookup

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ DNS record creation timeout after 20s"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "ExternalDNS may still be processing the DNSEndpoint resource"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check DNSEndpoint resources: kubectl get dnsendpoint -A"
  assert_contains "$output" "• Check ExternalDNS logs: kubectl logs -n external-dns -l app=external-dns --tail=50"
}

# =============================================================================
# external_dns: DNS endpoint not found but keeps trying
# =============================================================================
@test "wait_on_balancer: external_dns DNS endpoint not found but keeps trying until resolved" {
  kubectl() {
    case "$*" in
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status}")
        echo "not found"
        return 1
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Checking DNSEndpoint status: k-8-s-my-scope-scope-123-dns"
  assert_contains "$output" "✅ DNS record for my-scope.example.com is now resolvable"
  assert_contains "$output" "✨ ExternalDNS setup completed successfully"
}

# =============================================================================
# external_dns: DNS endpoint found with status
# =============================================================================
@test "wait_on_balancer: external_dns DNS endpoint found with status is displayed" {
  kubectl() {
    case "$*" in
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status}")
        echo '{"observedGeneration":2}'
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" '📋 DNSEndpoint status: {"observedGeneration":2}'
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
