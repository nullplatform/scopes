#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/notify_active_domains - domain activation
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export CONTEXT='{
    "scope": {
      "domains": [
        {"id": "dom-1", "name": "app.example.com"},
        {"id": "dom-2", "name": "api.example.com"}
      ]
    }
  }'

  np() {
    echo "np $*"
    return 0
  }
  export -f np
}

teardown() {
  unset CONTEXT
  unset -f np
}

# =============================================================================
# Success Case
# =============================================================================
@test "notify_active_domains: activates domains with correct logging" {
  run source "$BATS_TEST_DIRNAME/../notify_active_domains"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking for custom domains to activate..."
  assert_contains "$output" "📋 Found 2 custom domain(s) to activate"
  assert_contains "$output" "📝 Activating custom domain: app.example.com..."
  assert_contains "$output" "✅ Custom domain activated: app.example.com"
  assert_contains "$output" "📝 Activating custom domain: api.example.com..."
  assert_contains "$output" "✅ Custom domain activated: api.example.com"
  assert_contains "$output" "✨ Custom domain activation completed"
}

# =============================================================================
# No Domains Case
# =============================================================================
@test "notify_active_domains: skips when no domains configured" {
  export CONTEXT='{"scope": {"domains": []}}'

  run source "$BATS_TEST_DIRNAME/../notify_active_domains"

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Checking for custom domains to activate..."
  assert_contains "$output" "📋 No domains configured, skipping activation"
}

# =============================================================================
# Failure Case
# =============================================================================
@test "notify_active_domains: shows error output and troubleshooting when np fails" {
  np() {
    echo '{"error": "scope write error: request failed with status 403: Forbidden"}'
    return 1  # Simulate failure
  }
  export -f np

  run source "$BATS_TEST_DIRNAME/../notify_active_domains"

  [ "$status" -eq 0 ]  # Script continues with other domains
  assert_contains "$output" "❌ Failed to activate custom domain: app.example.com"
  assert_contains "$output" '📋 Error: {"error": "scope write error: request failed with status 403: Forbidden"}'
  assert_contains "$output" "scope write error"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "Domain ID dom-1 may not exist"
  assert_contains "$output" "Insufficient permissions (403 Forbidden)"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify domain exists: np scope domain get --id dom-1"
  assert_contains "$output" "Check API token permissions"
}

