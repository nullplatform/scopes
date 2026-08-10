#!/usr/bin/env bats
# =============================================================================
# Tests for scheduled_task/deployment/build_deployment.
#
# Mirrors k8s/deployment/tests/build_deployment.bats with a scheduled_task
# context (CronJob instead of Deployment). The same file-parameter regressions
# apply because scheduled_task reuses the k8s secret templates and ships its
# own deployment template that follows the same two-Secret + sanitized-name
# pattern.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"

  export OUTPUT_DIR="$(mktemp -d)"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-456"
  export REPLICAS="1"

  # scheduled_task reuses the k8s secret templates and ships its own
  # deployment template under scheduled_task/deployment/templates/.
  export DEPLOYMENT_TEMPLATE="$PROJECT_ROOT/scheduled_task/deployment/templates/deployment.yaml.tpl"
  export SECRET_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/secret.yaml.tpl"
  export SECRET_FILES_TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/secret-files.yaml.tpl"

  export CONTEXT='{}'

  # Mock gomplate for orchestration tests (any test that doesn't `unset -f`).
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
# File creation — confirms the script renders deployment + both Secrets
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

# =============================================================================
# Rendering tests — real gomplate, assert on rendered output
# =============================================================================
# Minimal context that satisfies the scheduled_task deployment template plus
# the shared k8s secret + secret-files templates. Includes a file param with
# (a) a display name that needs sanitizing and (b) a destination_path with a
# leading `[` to lock in YAML quoting at every insertion point.
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
      "cron": "*/5 * * * *",
      "concurrency_policy": "Forbid",
      "history_limit": {"successful": 3, "failed": 1},
      "retries": 0
    }
  },
  "deployment": {"id": "deploy-456"},
  "k8s_namespace": "ns-test",
  "k8s_modifiers": {},
  "asset": {"url": "example.com/app:latest"},
  "component": "app",
  "service_account_name": "",
  "region": "us-east-1",
  "logs_provider": "cloudwatch",
  "pull_secrets": {"ENABLED": false, "SECRETS": []},
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
  unset -f gomplate  # use the real gomplate binary

  export CONTEXT="$(_render_context)"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  local secret_file="$OUTPUT_DIR/secret-scope-123-deploy-456.yaml"
  local secret_files_file="$OUTPUT_DIR/secret-files-scope-123-deploy-456.yaml"
  local deploy_file="$OUTPUT_DIR/deployment-scope-123-deploy-456.yaml"

  assert_file_exists "$secret_file"
  assert_file_exists "$secret_files_file"
  assert_file_exists "$deploy_file"

  # The envFrom Secret must not carry any file-related keys, otherwise the
  # binary content would be injected as an env var and runc would reject it.
  ! grep -E 'app-(data|file)-' "$secret_file"

  # The files Secret holds only the binary content under a sanitized key.
  assert_contains "$(cat "$secret_files_file")" "name: s-scope-123-d-deploy-456-files"
  assert_contains "$(cat "$secret_files_file")" "app-file-api-p12-cert: QUFBQkJC"
  ! grep -E 'app-data-' "$secret_files_file"

  # The CronJob's application container gets a plain `env:` entry whose value
  # is the destination path, plus a volume mount reading from the files Secret.
  assert_contains "$(cat "$deploy_file")" "- name: app-data-api-p12-cert"
  # Leading `[` in the path makes YAML parse the value as a flow sequence
  # unless quoted — the four insertion points below all require quoting.
  assert_contains "$(cat "$deploy_file")" 'value: "/app-data/[2026-05-27] cert.p12"'
  assert_contains "$(cat "$deploy_file")" 'mountPath: "/app-data/[2026-05-27] cert.p12"'
  assert_contains "$(cat "$deploy_file")" 'subPath: "[2026-05-27] cert.p12"'
  assert_contains "$(cat "$deploy_file")" 'path: "[2026-05-27] cert.p12"'

  assert_contains "$(cat "$deploy_file")" "secretName: s-scope-123-d-deploy-456-files"
  assert_contains "$(cat "$deploy_file")" "key: app-file-api-p12-cert"
}

@test "build_deployment: secret-files renders empty when no file params" {
  unset -f gomplate

  export CONTEXT="$(_render_context | jq '.parameters.results |= map(select(.type != "file"))')"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  # gomplate skips writing the output when the template renders empty;
  # apply_templates handles missing/empty files gracefully.
  local secret_files_file="$OUTPUT_DIR/secret-files-scope-123-deploy-456.yaml"
  [ ! -f "$secret_files_file" ] || [ ! -s "$secret_files_file" ]
}

# =============================================================================
# Application-log routing annotation
# =============================================================================
# scheduled_task keeps its own copy of deployment.yaml.tpl (it is the one variant
# that overrides DEPLOYMENT_TEMPLATE in values.yaml), so the rendered annotations
# need their own coverage. The precedence chain that produces .logs_provider is
# shared and covered by k8s/deployment/tests/build_context.bats.

_annotations() {
  yq eval '.spec.jobTemplate.spec.template.metadata.annotations' \
    "$OUTPUT_DIR/deployment-scope-123-deploy-456.yaml"
}
_ann_keys() { _annotations | yq eval 'keys | .[]' -; }

@test "logs routing: cloudwatch emits the provider annotation plus the naming keys" {
  unset -f gomplate

  export CONTEXT="$(_render_context | jq '. + {logs_provider: "cloudwatch"}')"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  local ann
  ann="$(_annotations)"
  assert_contains "$ann" "nullplatform.logs.provider: cloudwatch"
  assert_contains "$ann" "nullplatform.logs.cloudwatch.log_group_name: nsps.appslug"
}

@test "logs routing: datadog emits the provider annotation and no cloudwatch keys" {
  unset -f gomplate

  export CONTEXT="$(_render_context | jq '. + {logs_provider: "datadog"}')"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  assert_contains "$(_annotations)" "nullplatform.logs.provider: datadog"
  assert_equal "$(_ann_keys | grep -c 'nullplatform.logs.cloudwatch')" "0"
}

@test "logs routing: the deprecated boolean annotations are gone" {
  unset -f gomplate

  for provider in cloudwatch datadog; do
    export CONTEXT="$(_render_context | jq --arg p "$provider" '. + {logs_provider: $p}')"

    run bash "$BATS_TEST_DIRNAME/../build_deployment"
    [ "$status" -eq 0 ]

    assert_equal "$(_ann_keys | grep -cE '^nullplatform\.logs\.(cloudwatch|datadog)$')" "0"
  done
}

@test "logs routing: a context without logs_provider still renders, defaulting to CloudWatch" {
  unset -f gomplate

  export CONTEXT="$(_render_context | jq 'del(.logs_provider)')"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  assert_contains "$(_annotations)" "nullplatform.logs.provider: cloudwatch"
}

@test "logs routing: cloudwatch region comes from context, not a hardcoded value" {
  unset -f gomplate

  # This template used to hardcode `region: us-east-1`, which silently pointed
  # every non-us-east-1 scheduled task at the wrong CloudWatch region.
  export CONTEXT="$(_render_context | jq '. + {logs_provider: "cloudwatch", region: "eu-west-1"}')"

  run bash "$BATS_TEST_DIRNAME/../build_deployment"
  [ "$status" -eq 0 ]

  assert_contains "$(_annotations)" "nullplatform.logs.cloudwatch.region: eu-west-1"
}
