#!/usr/bin/env bats
# =============================================================================
# Unit tests for apply_templates - template application with empty file handling
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  # Set required environment variables
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export ACTION="apply"
  export DRY_RUN="false"

  # Create temp directory for test files
  export OUTPUT_DIR="$(mktemp -d)"

  # Mock kubectl
  kubectl() {
    return 0
  }
  export -f kubectl

  # Mock backup_templates (sourced script)
  export MANIFEST_BACKUP='{"ENABLED":"false"}'
}

teardown() {
  rm -rf "$OUTPUT_DIR"
  unset OUTPUT_DIR
  unset ACTION
  unset DRY_RUN
  unset SERVICE_PATH
  unset MANIFEST_BACKUP
  unset -f kubectl
}

# =============================================================================
# Header Message Tests
# =============================================================================
@test "apply_templates: displays applying header message" {
  echo "apiVersion: v1" > "$OUTPUT_DIR/valid.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<EOF
📝 Applying templates...
📋 Directory: $OUTPUT_DIR
📋 Action: apply
📋 Dry run: false

📝 kubectl apply valid.yaml
📋 Manifest backup is disabled, skipping
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Test: Skips empty files (zero bytes)
# =============================================================================
@test "apply_templates: skips empty files (zero bytes)" {
  # Create an empty file
  touch "$OUTPUT_DIR/empty.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<EOF
📝 Applying templates...
📋 Directory: $OUTPUT_DIR
📋 Action: apply
📋 Dry run: false

📋 Skipping empty template: empty.yaml
📋 Manifest backup is disabled, skipping
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Test: Skips files with only whitespace
# =============================================================================
@test "apply_templates: skips files with only whitespace" {
  # Create a file with only whitespace
  echo "   " > "$OUTPUT_DIR/whitespace.yaml"
  echo "" >> "$OUTPUT_DIR/whitespace.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<EOF
📝 Applying templates...
📋 Directory: $OUTPUT_DIR
📋 Action: apply
📋 Dry run: false

📋 Skipping empty template: whitespace.yaml
📋 Manifest backup is disabled, skipping
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Test: Skips files with only newlines
# =============================================================================
@test "apply_templates: skips files with only newlines" {
  # Create a file with only newlines
  printf "\n\n\n" > "$OUTPUT_DIR/newlines.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<EOF
📝 Applying templates...
📋 Directory: $OUTPUT_DIR
📋 Action: apply
📋 Dry run: false

📋 Skipping empty template: newlines.yaml
📋 Manifest backup is disabled, skipping
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Test: Applies non-empty files
# =============================================================================
@test "apply_templates: applies non-empty files" {
  echo "apiVersion: v1" > "$OUTPUT_DIR/valid.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<EOF
📝 Applying templates...
📋 Directory: $OUTPUT_DIR
📋 Action: apply
📋 Dry run: false

📝 kubectl apply valid.yaml
📋 Manifest backup is disabled, skipping
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Test: Moves applied files to apply directory
# =============================================================================
@test "apply_templates: moves applied files to apply directory" {
  echo "apiVersion: v1" > "$OUTPUT_DIR/valid.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_file_exists "$OUTPUT_DIR/apply/valid.yaml"
  [ ! -f "$OUTPUT_DIR/valid.yaml" ]
}

# =============================================================================
# Test: Does not call kubectl for empty files
# =============================================================================
@test "apply_templates: does not call kubectl for empty files" {
  touch "$OUTPUT_DIR/empty.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<EOF
📝 Applying templates...
📋 Directory: $OUTPUT_DIR
📋 Action: apply
📋 Dry run: false

📋 Skipping empty template: empty.yaml
📋 Manifest backup is disabled, skipping
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Test: Handles delete action for empty files
# =============================================================================
@test "apply_templates: handles delete action for empty files" {
  export ACTION="delete"
  touch "$OUTPUT_DIR/empty.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  local expected
  expected=$(cat <<EOF
📝 Applying templates...
📋 Directory: $OUTPUT_DIR
📋 Action: delete
📋 Dry run: false

📋 Skipping empty template: empty.yaml
📋 Manifest backup is disabled, skipping
EOF
)
  assert_equal "$output" "$expected"
}

# =============================================================================
# Test: Dry run mode still skips empty files
# =============================================================================
@test "apply_templates: dry run mode still skips empty files" {
  export DRY_RUN="true"
  touch "$OUTPUT_DIR/empty.yaml"
  echo "apiVersion: v1" > "$OUTPUT_DIR/valid.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  # Dry run exits with 1
  [ "$status" -eq 1 ]
  local expected
  expected=$(cat <<EOF
📝 Applying templates...
📋 Directory: $OUTPUT_DIR
📋 Action: apply
📋 Dry run: true

📋 Skipping empty template: empty.yaml
📝 kubectl apply valid.yaml

📋 Dry run mode - no changes were made
EOF
)
  assert_equal "$output" "$expected"
}
