#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/notify_active_domains - domain activation
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

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
  local expected
  expected=$(cat <<'EOF'
🔍 Checking for custom domains to activate...
📋 Found 2 custom domain(s) to activate
📝 Activating custom domain: app.example.com...
✅ Custom domain activated: app.example.com
📝 Activating custom domain: api.example.com...
✅ Custom domain activated: api.example.com
✨ Custom domain activation completed
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# No Domains Case
# =============================================================================
@test "notify_active_domains: skips when no domains configured" {
  export CONTEXT='{"scope": {"domains": []}}'

  run source "$BATS_TEST_DIRNAME/../notify_active_domains"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<'EOF'
🔍 Checking for custom domains to activate...
📋 No domains configured, skipping activation
EOF
)
  assert_equal "$output" "$expected"
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
  # np fails identically for every domain, so both dom-1 and dom-2 produce a
  # full error block; the loop does not abort after the first failure.
  local expected
  expected=$(cat <<'EOF'
🔍 Checking for custom domains to activate...
📋 Found 2 custom domain(s) to activate
📝 Activating custom domain: app.example.com...
❌ Failed to activate custom domain: app.example.com
📋 Error: {"error": "scope write error: request failed with status 403: Forbidden"}
💡 Possible causes:
   - Domain ID dom-1 may not exist
   - Insufficient permissions (403 Forbidden)
   - API connectivity issues
🔧 How to fix:
   - Verify domain exists: np scope domain get --id dom-1
   - Check API token permissions
📝 Activating custom domain: api.example.com...
❌ Failed to activate custom domain: api.example.com
📋 Error: {"error": "scope write error: request failed with status 403: Forbidden"}
💡 Possible causes:
   - Domain ID dom-2 may not exist
   - Insufficient permissions (403 Forbidden)
   - API connectivity issues
🔧 How to fix:
   - Verify domain exists: np scope domain get --id dom-2
   - Check API token permissions
✨ Custom domain activation completed
EOF
)
  assert_equal "$output" "$expected"
}

