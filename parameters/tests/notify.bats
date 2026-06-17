#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/notify (dispatch with default fallback)
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/notify"
  export PROVIDER_DIR="$BATS_TEST_TMPDIR/fake_provider"
  mkdir -p "$PROVIDER_DIR"
}

@test "notify: uses provider's notify when present" {
  cat > "$PROVIDER_DIR/notify" << 'EOF'
echo '{"success":true,"provider":"fake"}'
EOF

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" '"provider":"fake"'
}

@test "notify: falls back to default success when provider has no notify" {
  # Intentionally do NOT create $PROVIDER_DIR/notify

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_equal "$output" '{"success":true}'
}

@test "notify: provider's notify failure propagates" {
  cat > "$PROVIDER_DIR/notify" << 'EOF'
echo "ack failed" >&2
exit 7
EOF

  run bash "$SCRIPT"

  assert_equal "$status" "7"
  assert_contains "$output" "ack failed"
}
