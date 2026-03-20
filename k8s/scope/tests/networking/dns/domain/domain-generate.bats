#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/dns/domain/domain-generate
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/dns/domain/domain-generate"
}

# =============================================================================
# Basic domain generation with account slug
# =============================================================================
@test "domain-generate: generates domain with account slug" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api" \
    --domain="nullapps.io" \
    --useAccountSlug="true"

  [ "$status" -eq 0 ]
  assert_contains "$output" ".myaccount.nullapps.io"
  assert_contains "$output" "prod-webapp-api-"
}

# =============================================================================
# Domain generation without account slug
# =============================================================================
@test "domain-generate: generates domain without account slug" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api" \
    --domain="nullapps.io" \
    --useAccountSlug="false"

  [ "$status" -eq 0 ]
  assert_contains "$output" ".nullapps.io"
  assert_contains "$output" "prod-webapp-api-"
  # Should NOT contain account slug in domain
  [[ "$output" != *".myaccount."* ]]
}

# =============================================================================
# Default domain value
# =============================================================================
@test "domain-generate: uses default domain nullapps.io when not specified" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api"

  [ "$status" -eq 0 ]
  assert_contains "$output" ".myaccount.nullapps.io"
}

# =============================================================================
# Custom domain
# =============================================================================
@test "domain-generate: uses custom domain when specified" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api" \
    --domain="example.com" \
    --useAccountSlug="true"

  [ "$status" -eq 0 ]
  assert_contains "$output" ".myaccount.example.com"
}

# =============================================================================
# Long domain truncation
# =============================================================================
@test "domain-generate: truncates long domain to safe length" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="very-long-namespace-slug-that-is-quite-extended" \
    --applicationSlug="very-long-application-slug-name" \
    --scopeSlug="very-long-scope-slug-name" \
    --domain="nullapps.io" \
    --useAccountSlug="false"

  [ "$status" -eq 0 ]
  # The first_part (namespace-application-scope) should be truncated
  # Total first_part before hash should be max 57 chars
  local domain_output="$output"
  # Extract the part before the hash (everything before the 5-letter hash)
  local first_part
  first_part=$(echo "$domain_output" | sed 's/-[a-z]\{5\}\..*$//')
  local length=${#first_part}
  [ "$length" -le 57 ]
}

@test "domain-generate: strips trailing dashes after truncation" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="aaaaaaaaaaaaaaaaaaaaaaaa" \
    --applicationSlug="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" \
    --scopeSlug="c" \
    --domain="nullapps.io" \
    --useAccountSlug="false"

  [ "$status" -eq 0 ]
  # Should not have trailing dash before the hash
  [[ "$output" != *"--"*".nullapps.io" ]]
}

# =============================================================================
# Required parameters missing
# =============================================================================
@test "domain-generate: fails when accountSlug is missing" {
  run bash "$SCRIPT" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: accountSlug, namespaceSlug, applicationSlug, and scopeSlug are required"
}

@test "domain-generate: fails when namespaceSlug is missing" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --applicationSlug="webapp" \
    --scopeSlug="api"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: accountSlug, namespaceSlug, applicationSlug, and scopeSlug are required"
}

@test "domain-generate: fails when applicationSlug is missing" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --scopeSlug="api"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: accountSlug, namespaceSlug, applicationSlug, and scopeSlug are required"
}

@test "domain-generate: fails when scopeSlug is missing" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: accountSlug, namespaceSlug, applicationSlug, and scopeSlug are required"
}

@test "domain-generate: fails when no arguments provided" {
  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: accountSlug, namespaceSlug, applicationSlug, and scopeSlug are required"
}

# =============================================================================
# Unknown option
# =============================================================================
@test "domain-generate: fails on unknown option" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api" \
    --unknownFlag="value"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: Unknown option --unknownFlag=value"
}

# =============================================================================
# Help flag
# =============================================================================
@test "domain-generate: displays usage with --help" {
  run bash "$SCRIPT" --help

  [ "$status" -eq 0 ]
  assert_contains "$output" "Usage:"
  assert_contains "$output" "--accountSlug=VALUE"
  assert_contains "$output" "--namespaceSlug=VALUE"
  assert_contains "$output" "--applicationSlug=VALUE"
  assert_contains "$output" "--scopeSlug=VALUE"
}

# =============================================================================
# Hash consistency
# =============================================================================
@test "domain-generate: produces consistent hash for same input" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api" \
    --domain="nullapps.io" \
    --useAccountSlug="true"

  [ "$status" -eq 0 ]
  local first_result="$output"

  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api" \
    --domain="nullapps.io" \
    --useAccountSlug="true"

  [ "$status" -eq 0 ]
  assert_equal "$output" "$first_result"
}

@test "domain-generate: produces different hash for different input" {
  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="prod" \
    --applicationSlug="webapp" \
    --scopeSlug="api" \
    --domain="nullapps.io" \
    --useAccountSlug="true"

  [ "$status" -eq 0 ]
  local first_result="$output"

  run bash "$SCRIPT" \
    --accountSlug="myaccount" \
    --namespaceSlug="dev" \
    --applicationSlug="webapp" \
    --scopeSlug="api" \
    --domain="nullapps.io" \
    --useAccountSlug="true"

  [ "$status" -eq 0 ]
  [ "$output" != "$first_result" ]
}
