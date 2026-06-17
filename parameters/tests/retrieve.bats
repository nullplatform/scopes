#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/retrieve (dispatch)
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/retrieve"
  export PROVIDER_DIR="$BATS_TEST_TMPDIR/fake_provider"
  mkdir -p "$PROVIDER_DIR"
}

@test "retrieve: sources provider's retrieve and propagates stdout" {
  cat > "$PROVIDER_DIR/retrieve" << 'EOF'
echo '{"value":"the-actual-value"}'
EOF

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_equal "$output" '{"value":"the-actual-value"}'
}

@test "retrieve: provider script sees EXTERNAL_ID env var" {
  export EXTERNAL_ID="ext-abc-123"
  cat > "$PROVIDER_DIR/retrieve" << 'EOF'
echo "{\"echoed_external_id\":\"$EXTERNAL_ID\"}"
EOF

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "ext-abc-123"
}

@test "retrieve: fails when provider's retrieve doesn't exist" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
