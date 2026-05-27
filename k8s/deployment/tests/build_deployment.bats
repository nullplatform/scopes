#!/usr/bin/env bats
# =============================================================================
# Unit tests for deployment/build_deployment - template generation
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }
  export -f log

  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export OUTPUT_DIR="$(mktemp -d)"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-456"
  export REPLICAS="3"

  # Template paths
  export DEPLOYMENT_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/deployment.yaml.tpl"
  export SECRET_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/secret.yaml.tpl"
  export SCALING_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/scaling.yaml.tpl"
  export SERVICE_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/service.yaml.tpl"
  export PDB_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/pdb.yaml.tpl"

  export CONTEXT='{}'

  # Mock gomplate
  gomplate() {
    local out_file=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --out) out_file="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "apiVersion: v1" > "$out_file"
    return 0
  }
  export -f gomplate
}

teardown() {
  rm -rf "$OUTPUT_DIR"
  unset -f gomplate
}

# =============================================================================
# Success Logging Tests
# =============================================================================
@test "build_deployment: displays all expected log messages on success" {
  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 0 ]

  # Header messages
  assert_contains "$output" "📝 Building deployment templates..."
  assert_contains "$output" "📋 Output directory:"

  # Deployment template
  assert_contains "$output" "✅ Deployment template:"

  # Secret template
  assert_contains "$output" "✅ Secret template:"

  # Scaling template
  assert_contains "$output" "✅ Scaling template:"

  # Service template
  assert_contains "$output" "✅ Service template:"

  # PDB template
  assert_contains "$output" "✅ PDB template:"

  # Summary
  assert_contains "$output" "✨ All templates built successfully"
}

# =============================================================================
# Error Handling Tests
# =============================================================================
@test "build_deployment: fails when deployment template generation fails" {
  gomplate() {
    local file_arg=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --file) file_arg="$2"; shift 2 ;;
        --out) shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$file_arg" == *"deployment.yaml.tpl" ]]; then
      return 1
    fi
    return 0
  }
  export -f gomplate

  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to build deployment template"
}

@test "build_deployment: fails when secret template generation fails" {
  gomplate() {
    local file_arg=""
    local out_file=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --file) file_arg="$2"; shift 2 ;;
        --out) out_file="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$file_arg" == *"secret.yaml.tpl" ]]; then
      return 1
    fi
    echo "apiVersion: v1" > "$out_file"
    return 0
  }
  export -f gomplate

  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Failed to build secret template"
}

# =============================================================================
# File Creation Tests
# =============================================================================
@test "build_deployment: creates deployment file with correct name" {
  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 0 ]
  assert_file_exists "$OUTPUT_DIR/deployment-scope-123-deploy-456.yaml"
}

@test "build_deployment: creates secret file with correct name" {
  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 0 ]
  assert_file_exists "$OUTPUT_DIR/secret-scope-123-deploy-456.yaml"
}

@test "build_deployment: creates scaling file with correct name" {
  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 0 ]
  assert_file_exists "$OUTPUT_DIR/scaling-scope-123-deploy-456.yaml"
}

@test "build_deployment: creates service file with correct name" {
  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 0 ]
  assert_file_exists "$OUTPUT_DIR/service-scope-123-deploy-456.yaml"
}

@test "build_deployment: creates pdb file with correct name" {
  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 0 ]
  assert_file_exists "$OUTPUT_DIR/pdb-scope-123-deploy-456.yaml"
}

@test "build_deployment: removes context file after completion" {
  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 0 ]
  [ ! -f "$OUTPUT_DIR/context-scope-123.json" ]
}

# =============================================================================
# Rendering Tests — real gomplate, assert on rendered output
# =============================================================================
# These tests run the actual `gomplate` binary against the templates and
# verify the rendered Secret + Deployment YAML have the right shape.
#
# Regression guard for the file-type parameter bug: binary file content used
# to be stored under Secret key `app-data-<filename>` and then leaked into the
# container env block via `envFrom`, which runc rejects with
# `invalid environment variable ... contains nul byte`. The fix splits the
# Secret key into:
#   - app-data-<filename>  -> destination_path (string, env-safe)
#   - app-file-<filename>  -> raw binary (volume-mount-only)
# and updates the volume mount to read from the new key.

# Minimal context that satisfies all five templates' required fields.
# Includes both an `environment` and a `file` parameter so we can assert on
# the file-specific keys without ignoring the rest of the Secret content.
_render_context() {
  cat <<'JSON'
{
  "account": {"id": "acc1", "slug": "acct"},
  "namespace": {"id": "ns1", "slug": "nsps"},
  "application": {"id": "app1", "slug": "appslug"},
  "release": {"semver": "1.0.0"},
  "scope": {
    "id": "scope-123",
    "slug": "scopeslug",
    "domain": "x.example.com",
    "dimensions": {"env": "dev"},
    "capabilities": {
      "cpu_millicores": 100,
      "ram_memory": 128,
      "additional_ports": [],
      "scaling_type": "fixed",
      "autoscaling": {
        "min_replicas": 1,
        "max_replicas": 3,
        "target_cpu_utilization": 80,
        "target_memory_enabled": false,
        "target_memory_utilization": 80
      },
      "health_check": {"path": "/health", "timeout_seconds": 1, "period_seconds": 5, "initial_delay_seconds": 5}
    }
  },
  "deployment": {"id": "deploy-456"},
  "k8s_namespace": "ns-test",
  "k8s_modifiers": {},
  "asset": {"url": "example.com/app:latest"},
  "main_http_port": 8080,
  "traffic_image": "example.com/traffic:latest",
  "container_cpu_in_millicores": 50,
  "container_memory_in_memory": 64,
  "pull_secrets": {"ENABLED": false, "SECRETS": []},
  "region": "us-east-1",
  "component": "app",
  "service_account_name": "",
  "traffic_manager_config_map": "",
  "pdb_enabled": "false",
  "pdb_max_unavailable": "25%",
  "parameters": {
    "results": [
      {"type": "environment", "variable": "MY_VAR", "values": [{"value": "hello"}]},
      {"type": "file", "destination_path": "/etc/certs/test.p12", "values": [{"value": "data:application/x-pkcs12;base64,QUFBQkJC"}]}
    ]
  }
}
JSON
}

@test "build_deployment: file-type parameter renders path env var and separate binary key" {
  unset -f gomplate  # use the real gomplate binary, not the setup mock

  export CONTEXT="$(_render_context)"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  local secret_file="$OUTPUT_DIR/secret-scope-123-deploy-456.yaml"
  local deploy_file="$OUTPUT_DIR/deployment-scope-123-deploy-456.yaml"

  assert_file_exists "$secret_file"
  assert_file_exists "$deploy_file"

  # Secret: app-data-<filename> holds the base64-encoded destination path,
  # so envFrom injects a NUL-byte-free env var.
  local expected_path_b64
  expected_path_b64=$(printf '%s' '/etc/certs/test.p12' | base64)
  assert_contains "$(cat "$secret_file")" "app-data-test.p12: ${expected_path_b64}"

  # Secret: app-file-<filename> holds the raw base64 binary content for the
  # volume mount.
  assert_contains "$(cat "$secret_file")" "app-file-test.p12: QUFBQkJC"

  # Regression guard: the app-data key MUST NEVER carry the raw binary
  # (that's the original bug — runc rejects NUL bytes in env vars).
  ! grep -E '^[[:space:]]*app-data-test\.p12:[[:space:]]+QUFBQkJC[[:space:]]*$' "$secret_file"

  # Deployment: the volume mount items reference the binary key.
  assert_contains "$(cat "$deploy_file")" "key: app-file-test.p12"

  # Regression guard: the volume mount must not read from the env-var key,
  # otherwise the materialized file would contain the path string, not the cert.
  ! grep -F 'key: app-data-test.p12' "$deploy_file"
}
