#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/store (dispatch)
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/store"
  export PROVIDER_DIR="$BATS_TEST_TMPDIR/fake_provider"
  mkdir -p "$PROVIDER_DIR"
}

@test "store: sources provider's store and propagates stdout" {
  cat > "$PROVIDER_DIR/store" << 'EOF'
echo '{"external_id":"test-id","metadata":{"k":"v"}}'
EOF

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_equal "$output" '{"external_id":"test-id","metadata":{"k":"v"}}'
}

@test "store: provider script sees PROVIDER_DIR env var" {
  cat > "$PROVIDER_DIR/store" << 'EOF'
echo "{\"provider_dir\":\"$PROVIDER_DIR\"}"
EOF

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "\"provider_dir\":\"$PROVIDER_DIR\""
}

@test "store: fails when provider's store doesn't exist" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "store: provider script error propagates exit code" {
  cat > "$PROVIDER_DIR/store" << 'EOF'
echo "fatal" >&2
exit 1
EOF

  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  assert_contains "$output" "fatal"
}
