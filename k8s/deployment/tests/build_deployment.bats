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
