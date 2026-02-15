#!/usr/bin/env bats
# Unit tests for diagnose/utils/diagnose_utils

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../utils/diagnose_utils"

  export NP_OUTPUT_DIR="$(mktemp -d)"
  export NP_ACTION_CONTEXT='{
    "notification": {"id": "action-123", "service": {"id": "service-456"}}
  }'

  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  export SCRIPT_LOG_FILE="$(mktemp)"
  echo "test log line 1" > "$SCRIPT_LOG_FILE"
  echo "test log line 2" >> "$SCRIPT_LOG_FILE"

  np() { return 0; }
  export -f np
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE" "$SCRIPT_LOG_FILE"
  unset NP_OUTPUT_DIR NP_ACTION_CONTEXT SCRIPT_OUTPUT_FILE SCRIPT_LOG_FILE
  unset -f np
}

# Strip ANSI color codes from output for clean assertions
strip_ansi() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# =============================================================================
# Print Functions
# =============================================================================
@test "print_success: outputs green checkmark with message" {
  run print_success "Test message"

  [ "$status" -eq 0 ]
  local clean=$(strip_ansi "$output")
  assert_contains "$clean" "✓ Test message"
}

@test "print_error: outputs red X with message" {
  run print_error "Error message"

  [ "$status" -eq 0 ]
  local clean=$(strip_ansi "$output")
  assert_contains "$clean" "✗ Error message"
}

@test "print_warning: outputs yellow warning with message" {
  run print_warning "Warning message"

  [ "$status" -eq 0 ]
  local clean=$(strip_ansi "$output")
  assert_contains "$clean" "⚠ Warning message"
}

@test "print_info: outputs cyan info with message" {
  run print_info "Info message"

  [ "$status" -eq 0 ]
  local clean=$(strip_ansi "$output")
  assert_contains "$clean" "ℹ Info message"
}

@test "print_action: outputs wrench emoji with message" {
  run print_action "Action message"

  [ "$status" -eq 0 ]
  local clean=$(strip_ansi "$output")
  assert_contains "$clean" "🔧 Action message"
}

# =============================================================================
# require_resources
# =============================================================================
@test "require_resources: returns 0 when resources exist" {
  run require_resources "pods" "pod-1 pod-2" "app=test" "default"

  [ "$status" -eq 0 ]
}

@test "require_resources: returns 1 and shows skip message when resources empty" {
  update_check_result() { return 0; }
  export -f update_check_result

  run require_resources "pods" "" "app=test" "default"

  [ "$status" -eq 1 ]
  local clean=$(strip_ansi "$output")
  assert_contains "$clean" "⚠ No pods found with labels app=test in namespace default, check was skipped."
}

# =============================================================================
# require_pods / require_services / require_ingresses
# =============================================================================
@test "require_pods: returns 0 when pods exist, 1 when empty" {
  export PODS_FILE="$(mktemp)"
  export LABEL_SELECTOR="app=test"
  export NAMESPACE="default"

  # Test with pods
  echo '{"items":[{"metadata":{"name":"pod-1"}}]}' > "$PODS_FILE"
  run require_pods
  [ "$status" -eq 0 ]

  # Test without pods
  echo '{"items":[]}' > "$PODS_FILE"
  update_check_result() { return 0; }
  export -f update_check_result
  run require_pods
  [ "$status" -eq 1 ]

  rm -f "$PODS_FILE"
}

@test "require_services: returns 0 when services exist, 1 when empty" {
  export SERVICES_FILE="$(mktemp)"
  export LABEL_SELECTOR="app=test"
  export NAMESPACE="default"

  # Test with services
  echo '{"items":[{"metadata":{"name":"svc-1"}}]}' > "$SERVICES_FILE"
  run require_services
  [ "$status" -eq 0 ]

  # Test without services
  echo '{"items":[]}' > "$SERVICES_FILE"
  update_check_result() { return 0; }
  export -f update_check_result
  run require_services
  [ "$status" -eq 1 ]

  rm -f "$SERVICES_FILE"
}

@test "require_ingresses: returns 0 when ingresses exist" {
  export INGRESSES_FILE="$(mktemp)"
  export SCOPE_LABEL_SELECTOR="scope_id=123"
  export NAMESPACE="default"

  echo '{"items":[{"metadata":{"name":"ing-1"}}]}' > "$INGRESSES_FILE"
  run require_ingresses
  [ "$status" -eq 0 ]

  rm -f "$INGRESSES_FILE"
}

# =============================================================================
# update_check_result - Basic Operations
# =============================================================================
@test "update_check_result: updates status and evidence" {
  update_check_result --status "success" --evidence '{"key":"value"}'

  status_result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$status_result" "success"

  evidence_result=$(jq -r '.evidence.key' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$evidence_result" "value"
}

@test "update_check_result: includes logs from SCRIPT_LOG_FILE" {
  update_check_result --status "success" --evidence "{}"

  logs_count=$(jq -r '.logs | length' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$logs_count" "2"

  first_log=$(jq -r '.logs[0]' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$first_log" "test log line 1"

  second_log=$(jq -r '.logs[1]' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$second_log" "test log line 2"
}

@test "update_check_result: normalizes status to lowercase" {
  update_check_result --status "SUCCESS" --evidence "{}"

  result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$result" "success"
}

# =============================================================================
# update_check_result - Timestamps
# =============================================================================
@test "update_check_result: sets start_at for running status (ISO 8601 format)" {
  update_check_result --status "running" --evidence "{}"

  start_at=$(jq -r '.start_at' "$SCRIPT_OUTPUT_FILE")
  assert_not_empty "$start_at"
  assert_contains "$start_at" "T"
  assert_contains "$start_at" "Z"
}

@test "update_check_result: sets end_at for success and failed status" {
  # Test success
  update_check_result --status "success" --evidence "{}"
  end_at=$(jq -r '.end_at' "$SCRIPT_OUTPUT_FILE")
  assert_not_empty "$end_at"

  # Reset and test failed
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"
  update_check_result --status "failed" --evidence "{}"
  end_at=$(jq -r '.end_at' "$SCRIPT_OUTPUT_FILE")
  assert_not_empty "$end_at"
}

# =============================================================================
# update_check_result - Error Handling
# =============================================================================
@test "update_check_result: fails with 'File not found' when output file missing" {
  rm -f "$SCRIPT_OUTPUT_FILE"

  run update_check_result --status "success" --evidence "{}"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: File not found: $SCRIPT_OUTPUT_FILE"
}

@test "update_check_result: fails with 'is evidence valid JSON' for invalid JSON" {
  run update_check_result --status "success" --evidence "not-json"

  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: Failed to update JSON (is evidence valid JSON?)"
}

@test "update_check_result: fails with 'status and evidence are required' when missing" {
  run update_check_result --evidence "{}"
  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: status and evidence are required"

  run update_check_result --status "success"
  [ "$status" -eq 1 ]
  assert_contains "$output" "Error: status and evidence are required"
}

# =============================================================================
# update_check_result - Positional Arguments
# =============================================================================
@test "update_check_result: supports positional arguments (legacy API)" {
  update_check_result "success" '{"test":"value"}'

  status_result=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$status_result" "success"

  evidence=$(jq -r '.evidence.test' "$SCRIPT_OUTPUT_FILE")
  assert_equal "$evidence" "value"
}

# =============================================================================
# update_check_result - Log Limits
# =============================================================================
@test "update_check_result: limits logs to 20 lines" {
  for i in {1..30}; do
    echo "log line $i" >> "$SCRIPT_LOG_FILE"
  done

  update_check_result --status "success" --evidence "{}"

  logs_count=$(jq -r '.logs | length' "$SCRIPT_OUTPUT_FILE")
  [ "$logs_count" -le 20 ]
}

# =============================================================================
# notify_results
# =============================================================================
@test "notify_results: fails with 'No JSON result files found' when empty" {
  rm -rf "$NP_OUTPUT_DIR"/*

  run notify_results

  [ "$status" -eq 1 ]
  local clean=$(strip_ansi "$output")
  assert_contains "$clean" "⚠ No JSON result files found in $NP_OUTPUT_DIR"
}

@test "notify_results: succeeds when JSON files exist" {
  echo '{"category":"scope","status":"success","evidence":{}}' > "$NP_OUTPUT_DIR/test.json"

  run notify_results

  [ "$status" -eq 0 ]
}

@test "notify_results: excludes files in data directory" {
  mkdir -p "$NP_OUTPUT_DIR/data"
  echo '{"should":"be excluded"}' > "$NP_OUTPUT_DIR/data/pods.json"

  run notify_results

  [ "$status" -eq 1 ]
  local clean=$(strip_ansi "$output")
  assert_contains "$clean" "⚠ No JSON result files found in $NP_OUTPUT_DIR"
}
