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
  export SECRET_FILES_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/secret-files.yaml.tpl"
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

@test "build_deployment: creates secret-files file with correct name" {
  run bash "$BATS_TEST_DIRNAME/../build_deployment"

  [ "$status" -eq 0 ]
  assert_file_exists "$OUTPUT_DIR/secret-files-scope-123-deploy-456.yaml"
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
# to be stored under Secret key `app-data-<filename>` in the env-var Secret,
# which then leaked into the container env block via `envFrom`, which runc
# rejects with `invalid environment variable ... contains nul byte`. The fix
# splits the storage into two Secrets:
#   - s-<scope>-d-<deploy>        env-only, consumed via envFrom (safe)
#   - s-<scope>-d-<deploy>-files  binary-only, consumed only by the volume mount
# Plus a plain `env:` entry on the application container that carries the
# file's destination path under name `app-data-<filename>`.

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
      "cpu_millicores_limit": 200,
      "ram_memory_limit": 256,
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
      {"type": "file", "name": "API P12 Cert!", "destination_path": "/app-data/[2026-05-27] cert.p12", "values": [{"value": "data:application/x-pkcs12;base64,QUFBQkJC"}]}
    ]
  }
}
JSON
}

@test "build_deployment: file-type parameter splits binary into a separate Secret" {
  unset -f gomplate  # use the real gomplate binary, not the setup mock

  export CONTEXT="$(_render_context)"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  local secret_file="$OUTPUT_DIR/secret-scope-123-deploy-456.yaml"
  local secret_files_file="$OUTPUT_DIR/secret-files-scope-123-deploy-456.yaml"
  local deploy_file="$OUTPUT_DIR/deployment-scope-123-deploy-456.yaml"

  assert_file_exists "$secret_file"
  assert_file_exists "$secret_files_file"
  assert_file_exists "$deploy_file"

  # The env-var Secret MUST NOT contain anything that pulls in binary content
  # via envFrom. Both app-data-* and app-file-* keys are forbidden here.
  ! grep -E 'app-(data|file)-' "$secret_file"

  # Param name "API P12 Cert!" sanitizes to api-p12-cert (lowercase, runs of
  # non-alphanumeric collapse to '-', leading/trailing '-' trimmed). The same
  # token is reused as env name suffix, Secret data key, and volume name.
  assert_contains "$(cat "$secret_files_file")" "name: s-scope-123-d-deploy-456-files"
  assert_contains "$(cat "$secret_files_file")" "app-file-api-p12-cert: QUFBQkJC"
  ! grep -E 'app-data-' "$secret_files_file"

  # The deployment exposes the destination path to the app via a plain `env:`
  # entry on the application container (not via any Secret) — no NUL bytes,
  # and the env var name is derived from the parameter's display name.
  assert_contains "$(cat "$deploy_file")" "- name: app-data-api-p12-cert"
  # The path starts with `[`, which YAML parses as a flow sequence unless the
  # value is quoted. mountPath, subPath, path, and the env value must all be
  # quoted; otherwise the deployment agent fails with `did not find expected key`.
  assert_contains "$(cat "$deploy_file")" 'value: "/app-data/[2026-05-27] cert.p12"'
  assert_contains "$(cat "$deploy_file")" 'mountPath: "/app-data/[2026-05-27] cert.p12"'
  assert_contains "$(cat "$deploy_file")" 'subPath: "[2026-05-27] cert.p12"'
  assert_contains "$(cat "$deploy_file")" 'path: "[2026-05-27] cert.p12"'

  # The volume mount reads bytes from the files Secret, with key matching the
  # one produced by secret-files.yaml.tpl.
  assert_contains "$(cat "$deploy_file")" "secretName: s-scope-123-d-deploy-456-files"
  assert_contains "$(cat "$deploy_file")" "key: app-file-api-p12-cert"
}

@test "build_deployment: secret-files renders empty when no file params" {
  unset -f gomplate

  # Same context as _render_context but with the file-type param removed.
  export CONTEXT="$(_render_context | jq '.parameters.results |= map(select(.type != "file"))')"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  # gomplate skips writing the output file when the template renders empty,
  # which is the signal to apply_templates (which iterates the OUTPUT_DIR and
  # skips zero-byte/missing files) to not create an empty files-Secret in the
  # cluster.
  local secret_files_file="$OUTPUT_DIR/secret-files-scope-123-deploy-456.yaml"
  [ ! -f "$secret_files_file" ] || [ ! -s "$secret_files_file" ]
}
