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
  unset KUBECTL_DELETE_TIMEOUT_SECONDS
  unset K8S_NAMESPACE
  unset SKIP_WHEN_EMPTY
  unset -f kubectl
}

# =============================================================================
# Header Message Tests
# =============================================================================
@test "apply_templates: displays applying header message" {
  echo "apiVersion: v1" > "$OUTPUT_DIR/valid.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Applying templates..."
  assert_contains "$output" "📋 Directory:"
  assert_contains "$output" "📋 Action: apply"
  assert_contains "$output" "📋 Dry run: false"
}

# =============================================================================
# Test: Skips empty files (zero bytes)
# =============================================================================
@test "apply_templates: skips empty files (zero bytes)" {
  # Create an empty file
  touch "$OUTPUT_DIR/empty.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Skipping empty template: empty.yaml"
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
  assert_contains "$output" "📋 Skipping empty template: whitespace.yaml"
}

# =============================================================================
# Test: Skips files with only newlines
# =============================================================================
@test "apply_templates: skips files with only newlines" {
  # Create a file with only newlines
  printf "\n\n\n" > "$OUTPUT_DIR/newlines.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Skipping empty template: newlines.yaml"
}

# =============================================================================
# Test: Applies non-empty files
# =============================================================================
@test "apply_templates: applies non-empty files" {
  echo "apiVersion: v1" > "$OUTPUT_DIR/valid.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 kubectl apply valid.yaml"
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
  assert_contains "$output" "📋 Skipping empty template: empty.yaml"
}

# =============================================================================
# Test: Handles delete action for empty files
# =============================================================================
@test "apply_templates: handles delete action for empty files" {
  export ACTION="delete"
  touch "$OUTPUT_DIR/empty.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Skipping empty template"
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
  assert_contains "$output" "📋 Skipping empty template: empty.yaml"
  assert_contains "$output" "📋 Dry run mode - no changes were made"
}

@test "apply_templates: delete waits at most 300 seconds by default" {
  export ACTION="delete"
  echo "apiVersion: v1" > "$OUTPUT_DIR/ingress-1-2.yaml"
  kubectl() { echo "kubectl $*"; }
  export -f kubectl

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--ignore-not-found=true --timeout=300s"
}

@test "apply_templates: delete honors KUBECTL_DELETE_TIMEOUT_SECONDS" {
  export ACTION="delete"
  export KUBECTL_DELETE_TIMEOUT_SECONDS="45"
  echo "apiVersion: v1" > "$OUTPUT_DIR/ingress-1-2.yaml"
  kubectl() { echo "kubectl $*"; }
  export -f kubectl

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "--timeout=45s"
}

@test "apply_templates: apply does not set a delete timeout" {
  echo "apiVersion: v1" > "$OUTPUT_DIR/valid.yaml"
  kubectl() { echo "kubectl $*"; }
  export -f kubectl

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  [[ "$output" != *"--timeout"* ]] || false
}

@test "apply_templates: fails on an invalid KUBECTL_DELETE_TIMEOUT_SECONDS" {
  export ACTION="delete"
  export KUBECTL_DELETE_TIMEOUT_SECONDS="5m"
  echo "apiVersion: v1" > "$OUTPUT_DIR/ingress-1-2.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ KUBECTL_DELETE_TIMEOUT_SECONDS must be a positive integer, got: '5m'"
}

@test "apply_templates: explains a delete that timed out waiting for finalizers" {
  export ACTION="delete"
  export K8S_NAMESPACE="test-namespace"
  echo "apiVersion: v1" > "$OUTPUT_DIR/ingress-1-2.yaml"
  kubectl() {
    echo 'error: timed out waiting for the condition on ingresses/k-8-s-my-app-123-grpc-9010-internet-facing' >&2
    return 1
  }
  export -f kubectl

  run bash "$SERVICE_PATH/apply_templates"

  assert_contains "$output" "❌ Failed to apply ingress-1-2.yaml"
  assert_contains "$output" "⚠️  ingress-1-2.yaml was not deleted within 300s"
  assert_contains "$output" "   💡 Possible causes:"
  assert_contains "$output" "      - A finalizer is blocking the deletion and the controller that owns it is not removing it"
  assert_contains "$output" "        (for an ingress, the AWS Load Balancer Controller failing to reconcile its ALB)"
  assert_contains "$output" "   🔧 How to fix:"
  assert_contains "$output" "      - Find the objects stuck in deletion (they have a deletionTimestamp) and their finalizers in namespace test-namespace"
  assert_contains "$output" "      - Check the logs of the controller that owns the finalizer"
  assert_contains "$output" "      - Raise KUBECTL_DELETE_TIMEOUT_SECONDS if the controller only needs more time"
}

@test "apply_templates: fails on an empty KUBECTL_DELETE_TIMEOUT_SECONDS" {
  export ACTION="delete"
  export KUBECTL_DELETE_TIMEOUT_SECONDS=""
  echo "apiVersion: v1" > "$OUTPUT_DIR/ingress-1-2.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ KUBECTL_DELETE_TIMEOUT_SECONDS must be a positive integer, got: ''"
}

# =============================================================================
# SKIP_WHEN_EMPTY (opt-in): nothing to apply/delete closes the step as skipped
# =============================================================================
mock_np_step_skip() {
  np_step_skip() { echo "np_step_skip: $*"; }
  export -f np_step_skip
}

@test "apply_templates: without opt-in, no templates does not skip the step" {
  mock_np_step_skip

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  [[ "$output" != *"np_step_skip"* ]] || false
}

@test "apply_templates: SKIP_WHEN_EMPTY with no templates closes the step as skipped" {
  mock_np_step_skip
  export SKIP_WHEN_EMPTY=true

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "np_step_skip: no manifests to apply"
}

@test "apply_templates: SKIP_WHEN_EMPTY with only empty templates closes the step as skipped" {
  mock_np_step_skip
  export SKIP_WHEN_EMPTY=true
  export ACTION="delete"
  touch "$OUTPUT_DIR/empty.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  assert_contains "$output" "np_step_skip: no manifests to delete"
}

@test "apply_templates: SKIP_WHEN_EMPTY with a manifest does not skip the step" {
  mock_np_step_skip
  export SKIP_WHEN_EMPTY=true
  echo "apiVersion: v1" > "$OUTPUT_DIR/valid.yaml"

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  [[ "$output" != *"np_step_skip"* ]] || false
}

@test "apply_templates: SKIP_WHEN_EMPTY without np_step_skip defined is silent" {
  unset -f np_step_skip
  export SKIP_WHEN_EMPTY=true

  run bash "$SERVICE_PATH/apply_templates"

  [ "$status" -eq 0 ]
  [[ "$output" != *"np_step_skip"* ]] || false
  [[ "$output" != *"command not found"* ]] || false
}
