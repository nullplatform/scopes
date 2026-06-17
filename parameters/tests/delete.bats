#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/delete (dispatch)
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/delete"
  export PROVIDER_DIR="$BATS_TEST_TMPDIR/fake_provider"
  mkdir -p "$PROVIDER_DIR"
}

@test "delete: sources provider's delete and propagates stdout" {
  cat > "$PROVIDER_DIR/delete" << 'EOF'
echo '{"success":true}'
EOF

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_equal "$output" '{"success":true}'
}

@test "delete: provider script sees EXTERNAL_ID env var" {
  export EXTERNAL_ID="ext-to-delete"
  cat > "$PROVIDER_DIR/delete" << 'EOF'
echo "{\"deleted\":\"$EXTERNAL_ID\"}"
EOF

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "ext-to-delete"
}

@test "delete: fails when provider's delete doesn't exist" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
