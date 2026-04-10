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

  # Mock kubectl: DNS endpoint found and reconciled by default
  kubectl() {
    case "$*" in
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.metadata.generation}")
        echo "1"
        return 0
        ;;
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status.observedGeneration}")
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
# external_dns: Success on first attempt (generation matches observedGeneration)
# =============================================================================
@test "wait_on_balancer: external_dns success on first attempt" {
  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Waiting for balancer/DNS setup to complete..."
  assert_contains "$output" "📋 Waiting for ExternalDNS to reconcile DNSEndpoint: k-8-s-my-scope-scope-123-dns"
  assert_contains "$output" "🔍 Checking DNSEndpoint reconciliation (attempt 1/"
  assert_contains "$output" "📋 Generation: 1, ObservedGeneration: 1"
  assert_contains "$output" "✅ DNSEndpoint k-8-s-my-scope-scope-123-dns reconciled (generation 1)"
  assert_contains "$output" "✅ DNS record for my-scope.example.com should now be propagating"
  assert_contains "$output" "✨ ExternalDNS reconciliation completed successfully"
}

# =============================================================================
# external_dns: Success after retries (observedGeneration catches up)
# =============================================================================
@test "wait_on_balancer: external_dns success after retries" {
  export ATTEMPT_FILE=$(mktemp)
  echo "0" > "$ATTEMPT_FILE"
  kubectl() {
    case "$*" in
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.metadata.generation}")
        echo "1"
        return 0
        ;;
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status.observedGeneration}")
        local count=$(cat "$ATTEMPT_FILE")
        count=$((count + 1))
        echo "$count" > "$ATTEMPT_FILE"
        if [ "$count" -ge 2 ]; then
          echo "1"
        else
          echo ""
        fi
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"
  rm -f "$ATTEMPT_FILE"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking DNSEndpoint reconciliation (attempt 1/"
  assert_contains "$output" "📋 DNSEndpoint not yet reconciled, waiting 10s..."
  assert_contains "$output" "🔍 Checking DNSEndpoint reconciliation (attempt 2/"
  assert_contains "$output" "✅ DNSEndpoint k-8-s-my-scope-scope-123-dns reconciled (generation 1)"
  assert_contains "$output" "✨ ExternalDNS reconciliation completed successfully"
}

# =============================================================================
# external_dns: Timeout after MAX_ITERATIONS
# =============================================================================
@test "wait_on_balancer: external_dns timeout after MAX_ITERATIONS" {
  export MAX_ITERATIONS=2

  # observedGeneration never matches
  kubectl() {
    case "$*" in
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.metadata.generation}")
        echo "2"
        return 0
        ;;
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status.observedGeneration}")
        echo ""
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ DNSEndpoint reconciliation timeout after 20s"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "ExternalDNS may still be processing the DNSEndpoint resource"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Check ExternalDNS logs: kubectl logs -n external-dns -l app=external-dns --tail=50"
}

# =============================================================================
# external_dns: DNS endpoint not found but keeps trying until reconciled
# =============================================================================
@test "wait_on_balancer: external_dns DNS endpoint not found but keeps trying until reconciled" {
  export ATTEMPT_FILE=$(mktemp)
  echo "0" > "$ATTEMPT_FILE"
  kubectl() {
    case "$*" in
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.metadata.generation}")
        local count=$(cat "$ATTEMPT_FILE")
        count=$((count + 1))
        echo "$count" > "$ATTEMPT_FILE"
        if [ "$count" -ge 2 ]; then
          echo "1"
          return 0
        fi
        return 1
        ;;
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status.observedGeneration}")
        echo "1"
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"
  rm -f "$ATTEMPT_FILE"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 DNSEndpoint k-8-s-my-scope-scope-123-dns not found yet, waiting 10s..."
  assert_contains "$output" "✅ DNSEndpoint k-8-s-my-scope-scope-123-dns reconciled (generation 1)"
  assert_contains "$output" "✨ ExternalDNS reconciliation completed successfully"
}

# =============================================================================
# external_dns: Higher generation number reconciled
# =============================================================================
@test "wait_on_balancer: external_dns higher generation reconciled" {
  kubectl() {
    case "$*" in
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.metadata.generation}")
        echo "3"
        return 0
        ;;
      "get dnsendpoint k-8-s-my-scope-scope-123-dns -n default-namespace -o jsonpath={.status.observedGeneration}")
        echo "3"
        return 0
        ;;
    esac
  }
  export -f kubectl

  run bash "$BATS_TEST_DIRNAME/../wait_on_balancer"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Generation: 3, ObservedGeneration: 3"
  assert_contains "$output" "✅ DNSEndpoint k-8-s-my-scope-scope-123-dns reconciled (generation 3)"
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
