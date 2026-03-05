#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/dns/domain/generate_domain
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SERVICE_PATH="$(mktemp -d)"
  export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/dns/domain/generate_domain"

  # Create mock domain-generate binary
  mkdir -p "$SERVICE_PATH/scope/networking/dns/domain"
  cat > "$SERVICE_PATH/scope/networking/dns/domain/domain-generate" << 'MOCK'
#!/bin/bash
echo "generated.nullapps.io"
MOCK
  chmod +x "$SERVICE_PATH/scope/networking/dns/domain/domain-generate"

  # Mock np
  np() {
    echo "np called: $*"
    return 0
  }
  export -f np

  # Default environment
  export SCOPE_ID="scope-123"
  export DOMAIN="nullapps.io"
  export USE_ACCOUNT_SLUG="false"
  export CONTEXT='{
    "account": {"slug": "my-account"},
    "namespace": {"slug": "prod"},
    "application": {"slug": "webapp"},
    "scope": {"slug": "api", "domain": ""}
  }'
}

teardown() {
  rm -rf "$SERVICE_PATH"
  unset -f np
}

# =============================================================================
# Success flow
# =============================================================================
@test "generate_domain: full success flow" {
  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Generating scope domain..."
  assert_contains "$output" "📋 Generated domain: generated.nullapps.io"
  assert_contains "$output" "📝 Patching scope with domain..."
  assert_contains "$output" "np called: scope patch --id scope-123 --body {\"domain\":\"generated.nullapps.io\"}"
  assert_contains "$output" "✅ Scope domain updated"
}

# =============================================================================
# Calls domain-generate with correct params
# =============================================================================
@test "generate_domain: extracts slugs from CONTEXT and passes correct parameters" {
  cat > "$SERVICE_PATH/scope/networking/dns/domain/domain-generate" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
  echo "$arg"
done
MOCK
  chmod +x "$SERVICE_PATH/scope/networking/dns/domain/domain-generate"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "--accountSlug=my-account"
  assert_contains "$output" "--namespaceSlug=prod"
  assert_contains "$output" "--applicationSlug=webapp"
  assert_contains "$output" "--scopeSlug=api"
  assert_contains "$output" "--domain=nullapps.io"
  assert_contains "$output" "--useAccountSlug=false"
}

# =============================================================================
# domain-generate failure
# =============================================================================
@test "generate_domain: fails with error details when domain-generate fails" {
  cat > "$SERVICE_PATH/scope/networking/dns/domain/domain-generate" << 'MOCK'
#!/bin/bash
echo "Error: generation failed" >&2
exit 1
MOCK
  chmod +x "$SERVICE_PATH/scope/networking/dns/domain/domain-generate"

  run bash -c 'source "$SCRIPT"'

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to generate scope domain"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The domain-generate binary returned an error"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Verify the input slugs are valid"
}

# =============================================================================
# Updates CONTEXT with scope domain
# =============================================================================
@test "generate_domain: updates CONTEXT with new scope domain" {
  run bash -c 'source "$SCRIPT" && echo "$CONTEXT" | jq -r ".scope.domain"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "generated.nullapps.io"
}
