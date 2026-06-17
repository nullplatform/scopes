#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/entrypoint — workflow routing by action
# Kind discrimination is NOT done at this layer (see build_context.bats).
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/entrypoint"

  # Build a fake SERVICE_PATH with a mirror of parameters/workflows/
  export SERVICE_PATH="$BATS_TEST_TMPDIR/service"
  mkdir -p "$SERVICE_PATH/parameters/workflows"
  for wf in store retrieve delete notify; do
    : > "$SERVICE_PATH/parameters/workflows/$wf.yaml"
  done

  # Mock `np` so eval $CMD echoes the command to stdout instead of calling the real CLI
  cat > "$BATS_TEST_TMPDIR/np" << 'EOF'
#!/bin/bash
echo "$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/np"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

teardown() {
  unset NP_ACTION_CONTEXT NOTIFICATION_ACTION OVERRIDES_PATH SERVICE_PATH
}

@test "entrypoint: fails when NP_ACTION_CONTEXT is empty" {
  unset NP_ACTION_CONTEXT

  run bash "$SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ NP_ACTION_CONTEXT is not set"
}

@test "entrypoint: fails when NOTIFICATION_ACTION has no action part" {
  export NP_ACTION_CONTEXT='{"notification":{"secret":true}}'
  export NOTIFICATION_ACTION="parameter"

  run bash "$SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ NOTIFICATION_ACTION is missing the action part"
}

@test "entrypoint: store action routes to store.yaml" {
  export NP_ACTION_CONTEXT='{"notification":{"secret":true}}'
  export NOTIFICATION_ACTION="parameter:store"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "store.yaml"
}

@test "entrypoint: retrieve action routes to retrieve.yaml" {
  export NP_ACTION_CONTEXT='{"notification":{"secret":true,"external_id":"abc"}}'
  export NOTIFICATION_ACTION="parameter:retrieve"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "retrieve.yaml"
}

@test "entrypoint: delete action routes to delete.yaml" {
  export NP_ACTION_CONTEXT='{"notification":{"secret":false,"external_id":"abc"}}'
  export NOTIFICATION_ACTION="parameter:delete"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "delete.yaml"
}

@test "entrypoint: notify action routes to notify.yaml" {
  export NP_ACTION_CONTEXT='{"notification":{"secret":true,"external_id":"abc"}}'
  export NOTIFICATION_ACTION="parameter:notify"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "notify.yaml"
}

@test "entrypoint: payload's .secret value does not affect routing" {
  # Run with secret=true
  export NOTIFICATION_ACTION="parameter:store"
  export NP_ACTION_CONTEXT='{"notification":{"secret":true}}'
  run bash "$SCRIPT"
  assert_equal "$status" "0"
  output_true="$output"

  # Run with secret=false
  export NP_ACTION_CONTEXT='{"notification":{"secret":false}}'
  run bash "$SCRIPT"
  assert_equal "$status" "0"

  # Both route to the same workflow path
  assert_equal "$output" "$output_true"
}

@test "entrypoint: fails when no matching workflow exists" {
  export NP_ACTION_CONTEXT='{"notification":{"secret":true}}'
  export NOTIFICATION_ACTION="parameter:nonexistent"

  run bash "$SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ No workflow found at"
}

@test "entrypoint: strips surrounding single quotes from NP_ACTION_CONTEXT" {
  export NP_ACTION_CONTEXT="'{\"notification\":{\"secret\":true}}'"
  export NOTIFICATION_ACTION="parameter:store"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "store.yaml"
}

@test "entrypoint: OVERRIDES_PATH appends --overrides for matching path" {
  export NP_ACTION_CONTEXT='{"notification":{"secret":true}}'
  export NOTIFICATION_ACTION="parameter:store"

  mkdir -p "$BATS_TEST_TMPDIR/override1/parameters/workflows"
  : > "$BATS_TEST_TMPDIR/override1/parameters/workflows/store.yaml"
  export OVERRIDES_PATH="$BATS_TEST_TMPDIR/override1"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  assert_contains "$output" "--overrides $BATS_TEST_TMPDIR/override1/parameters/workflows/store.yaml"
}

@test "entrypoint: OVERRIDES_PATH skips paths without the workflow file" {
  export NP_ACTION_CONTEXT='{"notification":{"secret":true}}'
  export NOTIFICATION_ACTION="parameter:store"

  mkdir -p "$BATS_TEST_TMPDIR/empty_override"
  export OVERRIDES_PATH="$BATS_TEST_TMPDIR/empty_override"

  run bash "$SCRIPT"

  assert_equal "$status" "0"
  [[ "$output" != *"--overrides $BATS_TEST_TMPDIR/empty_override"* ]]
}
