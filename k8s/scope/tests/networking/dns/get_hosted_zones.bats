#!/usr/bin/env bats
# =============================================================================
# Unit tests for scope/networking/dns/get_hosted_zones
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export SERVICE_PATH="$(mktemp -d)"
  export SCRIPT="$PROJECT_ROOT/k8s/scope/networking/dns/get_hosted_zones"
}

teardown() {
  rm -rf "$SERVICE_PATH"
}

# =============================================================================
# Both zones found
# =============================================================================
@test "get_hosted_zones: both zones found - displays IDs and creates directories" {
  export CONTEXT='{"providers":{"cloud-providers":{"networking":{"hosted_public_zone_id":"Z_PUBLIC_123","hosted_zone_id":"Z_PRIVATE_456"}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Getting hosted zones..."
  assert_contains "$output" "📋 Public Hosted Zone ID: Z_PUBLIC_123"
  assert_contains "$output" "📋 Private Hosted Zone ID: Z_PRIVATE_456"
  assert_contains "$output" "✅ Hosted zones loaded"
  assert_directory_exists "$SERVICE_PATH/tmp"
  assert_directory_exists "$SERVICE_PATH/output"
}

# =============================================================================
# Only public zone found
# =============================================================================
@test "get_hosted_zones: only public zone - succeeds and creates directories" {
  export CONTEXT='{"providers":{"cloud-providers":{"networking":{"hosted_public_zone_id":"Z_PUBLIC_123","hosted_zone_id":null}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Getting hosted zones..."
  assert_contains "$output" "📋 Public Hosted Zone ID: Z_PUBLIC_123"
  assert_contains "$output" "📋 Private Hosted Zone ID: null"
  assert_contains "$output" "✅ Hosted zones loaded"
  assert_directory_exists "$SERVICE_PATH/tmp"
  assert_directory_exists "$SERVICE_PATH/output"
}

# =============================================================================
# Only private zone found
# =============================================================================
@test "get_hosted_zones: only private zone - succeeds and creates directories" {
  export CONTEXT='{"providers":{"cloud-providers":{"networking":{"hosted_public_zone_id":null,"hosted_zone_id":"Z_PRIVATE_456"}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Getting hosted zones..."
  assert_contains "$output" "📋 Public Hosted Zone ID: null"
  assert_contains "$output" "📋 Private Hosted Zone ID: Z_PRIVATE_456"
  assert_contains "$output" "✅ Hosted zones loaded"
  assert_directory_exists "$SERVICE_PATH/tmp"
  assert_directory_exists "$SERVICE_PATH/output"
}

# =============================================================================
# Neither zone found
# =============================================================================
@test "get_hosted_zones: neither zone found - displays warning and exits 0" {
  export CONTEXT='{"providers":{"cloud-providers":{"networking":{"hosted_public_zone_id":null,"hosted_zone_id":null}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Getting hosted zones..."
  assert_contains "$output" "📋 Public Hosted Zone ID: null"
  assert_contains "$output" "📋 Private Hosted Zone ID: null"
  assert_contains "$output" "⚠️  No hosted zones found (neither public nor private)"
}

@test "get_hosted_zones: both zones empty strings - displays warning and exits 0" {
  export CONTEXT='{"providers":{"cloud-providers":{"networking":{"hosted_public_zone_id":"","hosted_zone_id":""}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "⚠️  No hosted zones found (neither public nor private)"
}

@test "get_hosted_zones: neither zone found - does not create directories" {
  export CONTEXT='{"providers":{"cloud-providers":{"networking":{"hosted_public_zone_id":null,"hosted_zone_id":null}}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  [ ! -d "$SERVICE_PATH/tmp" ]
  [ ! -d "$SERVICE_PATH/output" ]
}

# =============================================================================
# Missing networking keys
# =============================================================================
@test "get_hosted_zones: missing networking keys - displays warning and exits 0" {
  export CONTEXT='{"providers":{"cloud-providers":{}}}'

  run bash -c 'source "$SCRIPT"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "🔍 Getting hosted zones..."
  assert_contains "$output" "📋 Public Hosted Zone ID: null"
  assert_contains "$output" "📋 Private Hosted Zone ID: null"
  assert_contains "$output" "⚠️  No hosted zones found (neither public nor private)"
}
