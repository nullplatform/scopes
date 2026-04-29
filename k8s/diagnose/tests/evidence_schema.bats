#!/usr/bin/env bats
# =============================================================================
# Cross-cutting schema validation for all migrated checks.
# Verifies every check writes evidence following the documented schema:
#   { summary, severity, affected, details, suggested_actions }
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export LABEL_SELECTOR="app=test"
  export SCOPE_LABEL_SELECTOR="scope_id=123"
  export DEPLOYMENT_ID="deploy-1"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  # Set up empty data files so every check can require_*
  export PODS_FILE="$(mktemp)"
  export SERVICES_FILE="$(mktemp)"
  export ENDPOINTS_FILE="$(mktemp)"
  export INGRESSES_FILE="$(mktemp)"
  export SECRETS_FILE="$(mktemp)"
  export INGRESSCLASSES_FILE="$(mktemp)"
  export EVENTS_FILE="$(mktemp)"
  export ALB_CONTROLLER_PODS_FILE="$(mktemp)"
  export ALB_CONTROLLER_LOGS_DIR="$(mktemp -d)"
  for f in "$PODS_FILE" "$SERVICES_FILE" "$ENDPOINTS_FILE" "$INGRESSES_FILE" \
           "$SECRETS_FILE" "$INGRESSCLASSES_FILE" "$EVENTS_FILE" "$ALB_CONTROLLER_PODS_FILE"; do
    echo '{"items":[]}' > "$f"
  done

  kubectl() { return 0; }
  export -f kubectl
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR" "$ALB_CONTROLLER_LOGS_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE" "$SCRIPT_LOG_FILE" "$PODS_FILE" "$SERVICES_FILE" \
        "$ENDPOINTS_FILE" "$INGRESSES_FILE" "$SECRETS_FILE" "$INGRESSCLASSES_FILE" \
        "$EVENTS_FILE" "$ALB_CONTROLLER_PODS_FILE"
  unset -f kubectl
}

reset_output() {
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"
}

# Assert that the evidence object on $SCRIPT_OUTPUT_FILE has the canonical schema:
#   summary (string), severity in {critical, warning, info},
#   affected (array), details (object), suggested_actions (array)
assert_evidence_schema() {
  local check_name="$1"

  local summary severity affected_kind details_kind actions_kind
  summary=$(jq -r '.evidence.summary // empty' "$SCRIPT_OUTPUT_FILE")
  severity=$(jq -r '.evidence.severity // empty' "$SCRIPT_OUTPUT_FILE")
  affected_kind=$(jq -r '.evidence.affected | type' "$SCRIPT_OUTPUT_FILE")
  details_kind=$(jq -r '.evidence.details | type' "$SCRIPT_OUTPUT_FILE")
  actions_kind=$(jq -r '.evidence.suggested_actions | type' "$SCRIPT_OUTPUT_FILE")

  [[ -n "$summary" ]] || {
    echo "[$check_name] missing evidence.summary"
    cat "$SCRIPT_OUTPUT_FILE"
    return 1
  }

  case "$severity" in
    critical|warning|info) ;;
    *) echo "[$check_name] invalid severity: '$severity'"; return 1 ;;
  esac

  [[ "$affected_kind" == "array" ]] || { echo "[$check_name] evidence.affected must be array, got $affected_kind"; return 1; }
  [[ "$details_kind"  == "object" ]] || { echo "[$check_name] evidence.details must be object, got $details_kind"; return 1; }
  [[ "$actions_kind"  == "array" ]] || { echo "[$check_name] evidence.suggested_actions must be array, got $actions_kind"; return 1; }
}

# =============================================================================
# Schema validation: skipped path (require_*)
# All checks that call require_pods/services/ingresses must produce schema
# evidence when the resource list is empty.
# =============================================================================
SCOPE_CHECKS_REQUIRE_PODS=(
  image_pull_status memory_limits_check resource_availability storage_mounting
  container_port_health health_probe_endpoints pod_readiness container_crash_detection
)

SERVICE_CHECKS_REQUIRE_SERVICES=(
  service_selector_match service_endpoints service_port_configuration service_type_validation
)

NETWORKING_CHECKS_REQUIRE_INGRESSES=(
  ingress_class_validation ingress_host_rules ingress_backend_service
  ingress_tls_configuration ingress_controller_sync alb_capacity_check
)

@test "schema: scope checks emit valid skipped evidence when no pods" {
  for check in "${SCOPE_CHECKS_REQUIRE_PODS[@]}"; do
    reset_output
    source "$BATS_TEST_DIRNAME/../scope/$check" || true
    assert_evidence_schema "scope/$check (skipped)"

    status=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
    [[ "$status" == "skipped" ]] || { echo "scope/$check expected status=skipped, got $status"; return 1; }
  done
}

@test "schema: service checks emit valid skipped evidence when no services" {
  for check in "${SERVICE_CHECKS_REQUIRE_SERVICES[@]}"; do
    reset_output
    source "$BATS_TEST_DIRNAME/../service/$check" || true
    assert_evidence_schema "service/$check (skipped)"

    status=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
    [[ "$status" == "skipped" ]] || { echo "service/$check expected status=skipped, got $status"; return 1; }
  done
}

@test "schema: networking checks emit valid skipped evidence when no ingresses" {
  for check in "${NETWORKING_CHECKS_REQUIRE_INGRESSES[@]}"; do
    reset_output
    source "$BATS_TEST_DIRNAME/../networking/$check" || true
    assert_evidence_schema "networking/$check (skipped)"

    status=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
    [[ "$status" == "skipped" ]] || { echo "networking/$check expected status=skipped, got $status"; return 1; }
  done
}

# =============================================================================
# Schema validation: failed path for "no resources" existence checks
# (these don't use require_*; they emit failed evidence directly)
# =============================================================================
@test "schema: pod_existence emits valid failed evidence when no pods" {
  reset_output
  echo '{"items":[]}' > "$PODS_FILE"
  source "$BATS_TEST_DIRNAME/../scope/pod_existence" || true
  assert_evidence_schema "scope/pod_existence (failed)"

  status=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  [[ "$status" == "failed" ]] || { echo "expected failed, got $status"; return 1; }

  severity=$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")
  [[ "$severity" == "critical" ]] || { echo "expected critical, got $severity"; return 1; }
}

@test "schema: service_existence emits valid failed evidence when no services" {
  reset_output
  echo '{"items":[]}' > "$SERVICES_FILE"
  source "$BATS_TEST_DIRNAME/../service/service_existence" || true
  assert_evidence_schema "service/service_existence (failed)"

  status=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  [[ "$status" == "failed" ]] || return 1
}

@test "schema: ingress_existence emits valid failed evidence when no ingresses" {
  reset_output
  echo '{"items":[]}' > "$INGRESSES_FILE"
  source "$BATS_TEST_DIRNAME/../networking/ingress_existence" || true
  assert_evidence_schema "networking/ingress_existence (failed)"

  status=$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")
  [[ "$status" == "failed" ]] || return 1
}

# =============================================================================
# Schema validation: success path for existence checks
# =============================================================================
@test "schema: existence checks emit valid info evidence when resources exist" {
  # pod_existence
  reset_output
  echo '{"items":[{"metadata":{"name":"p1"}}]}' > "$PODS_FILE"
  source "$BATS_TEST_DIRNAME/../scope/pod_existence" || true
  assert_evidence_schema "scope/pod_existence (success)"
  [[ "$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")" == "info" ]] || return 1

  # service_existence
  reset_output
  echo '{"items":[{"metadata":{"name":"s1"}}]}' > "$SERVICES_FILE"
  source "$BATS_TEST_DIRNAME/../service/service_existence" || true
  assert_evidence_schema "service/service_existence (success)"
  [[ "$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")" == "info" ]] || return 1

  # ingress_existence
  reset_output
  echo '{"items":[{"metadata":{"name":"i1"},"spec":{"rules":[]}}]}' > "$INGRESSES_FILE"
  source "$BATS_TEST_DIRNAME/../networking/ingress_existence" || true
  assert_evidence_schema "networking/ingress_existence (success)"
  [[ "$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")" == "info" ]] || return 1
}

# =============================================================================
# A few targeted "critical" path checks with realistic failure data
# =============================================================================
@test "schema: image_pull_status emits valid critical evidence with affected pods" {
  reset_output
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "p1"},
    "spec": {"containers":[{"name":"app","image":"foo:bar"}]},
    "status": {"containerStatuses":[{"name":"app","state":{"waiting":{"reason":"ImagePullBackOff","message":"pull failed"}}}]}
  }]
}
EOF
  source "$BATS_TEST_DIRNAME/../scope/image_pull_status" || true
  assert_evidence_schema "scope/image_pull_status (failed)"

  [[ "$(jq -r '.status' "$SCRIPT_OUTPUT_FILE")" == "failed" ]] || return 1
  [[ "$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")" == "critical" ]] || return 1
  affected=$(jq -c '.evidence.affected' "$SCRIPT_OUTPUT_FILE")
  [[ "$affected" == '["p1"]' ]] || { echo "expected affected=[p1], got $affected"; return 1; }
}

@test "schema: memory_limits_check emits valid critical evidence on OOMKilled" {
  reset_output
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "oom-pod"},
    "spec": {"containers":[{"name":"app","resources":{"limits":{"memory":"128Mi"},"requests":{"memory":"64Mi"}}}]},
    "status": {"containerStatuses":[{"name":"app","lastState":{"terminated":{"reason":"OOMKilled","exitCode":137}}}]}
  }]
}
EOF
  source "$BATS_TEST_DIRNAME/../scope/memory_limits_check" || true
  assert_evidence_schema "scope/memory_limits_check (failed)"

  [[ "$(jq -r '.evidence.severity' "$SCRIPT_OUTPUT_FILE")" == "critical" ]] || return 1
  oom=$(jq -r '.evidence.details.oom_killed[0].memory_limit' "$SCRIPT_OUTPUT_FILE")
  [[ "$oom" == "128Mi" ]] || { echo "expected memory_limit=128Mi, got $oom"; return 1; }
}

@test "schema: resource_availability emits valid critical evidence with insufficient_cpu flag" {
  reset_output
  cat > "$PODS_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "unsched"},
    "status": {"phase":"Pending","conditions":[{"type":"PodScheduled","status":"False","reason":"Unschedulable","message":"0/3 nodes available: insufficient cpu"}]}
  }]
}
EOF
  source "$BATS_TEST_DIRNAME/../scope/resource_availability" || true
  assert_evidence_schema "scope/resource_availability (failed)"

  cpu=$(jq -r '.evidence.details.cluster_insufficient_cpu' "$SCRIPT_OUTPUT_FILE")
  [[ "$cpu" == "true" ]] || { echo "expected insufficient_cpu=true, got $cpu"; return 1; }
}

@test "schema: ingress_class_validation emits valid critical evidence on missing class" {
  reset_output
  cat > "$INGRESSES_FILE" << 'EOF'
{
  "items":[{"metadata":{"name":"my-ing"},"spec":{"ingressClassName":"missing-class"}}]
}
EOF
  echo '{"items":[]}' > "$INGRESSCLASSES_FILE"
  source "$BATS_TEST_DIRNAME/../networking/ingress_class_validation" || true
  assert_evidence_schema "networking/ingress_class_validation (failed)"

  affected=$(jq -c '.evidence.affected' "$SCRIPT_OUTPUT_FILE")
  [[ "$affected" == '["my-ing"]' ]] || return 1
}

