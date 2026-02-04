#!/usr/bin/env bats
# =============================================================================
# Unit tests for backup/backup_templates - manifest backup orchestration
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Set required environment variables
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
}

teardown() {
  unset MANIFEST_BACKUP
  unset SERVICE_PATH
}

# =============================================================================
# Test: Skips when backup is disabled (false)
# =============================================================================
@test "backup_templates: skips when BACKUP_ENABLED is false" {
  export MANIFEST_BACKUP='{"ENABLED":"false","TYPE":"s3"}'

  # Use a subshell to capture the return statement behavior
  run bash -c '
    source "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/test.yaml
  '

  assert_equal "$status" "0"
  assert_equal "$output" "📋 Manifest backup is disabled, skipping"
}

# =============================================================================
# Test: Skips when backup is disabled (null)
# =============================================================================
@test "backup_templates: skips when BACKUP_ENABLED is null" {
  export MANIFEST_BACKUP='{"TYPE":"s3"}'

  run bash -c '
    source "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/test.yaml
  '

  assert_equal "$status" "0"
  assert_equal "$output" "📋 Manifest backup is disabled, skipping"
}

# =============================================================================
# Test: Skips when MANIFEST_BACKUP is empty
# =============================================================================
@test "backup_templates: skips when MANIFEST_BACKUP is empty" {
  export MANIFEST_BACKUP='{}'

  run bash -c '
    source "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/test.yaml
  '

  assert_equal "$status" "0"
  assert_equal "$output" "📋 Manifest backup is disabled, skipping"
}

# =============================================================================
# Test: Fails with unsupported backup type - Error message
# =============================================================================
@test "backup_templates: fails with unsupported backup type error" {
  export MANIFEST_BACKUP='{"ENABLED":"true","TYPE":"gcs"}'

  run bash "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/test.yaml

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Unsupported manifest backup type: 'gcs'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "MANIFEST_BACKUP.TYPE configuration is invalid"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Set MANIFEST_BACKUP.TYPE to 's3' in values.yaml"
}

# =============================================================================
# Test: Parses action argument correctly
# =============================================================================
@test "backup_templates: parses action argument" {
  export MANIFEST_BACKUP='{"ENABLED":"true","TYPE":"s3","BUCKET":"test","PREFIX":"manifests"}'

  # Mock aws to avoid actual calls
  aws() {
    return 0
  }
  export -f aws
  export REGION="us-east-1"

  run bash -c '
    source "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/output/123/apply/test.yaml
  '

  assert_contains "$output" "📋 Action: apply"
}

# =============================================================================
# Test: Parses files argument correctly
# =============================================================================
@test "backup_templates: parses files argument" {
  export MANIFEST_BACKUP='{"ENABLED":"true","TYPE":"s3","BUCKET":"test","PREFIX":"manifests"}'

  # Mock aws to avoid actual calls
  aws() {
    return 0
  }
  export -f aws
  export REGION="us-east-1"

  run bash -c '
    source "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/output/123/apply/file1.yaml /tmp/output/123/apply/file2.yaml
  '

  assert_contains "$output" "📋 Files: 2"
}

# =============================================================================
# Test: Calls s3 backup for s3 type
# =============================================================================
@test "backup_templates: calls s3 backup for s3 type" {
  export MANIFEST_BACKUP='{"ENABLED":"true","TYPE":"s3","BUCKET":"my-bucket","PREFIX":"backups"}'

  # Mock aws to avoid actual calls
  aws() {
    return 0
  }
  export -f aws
  export REGION="us-east-1"

  run bash -c '
    source "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/output/123/apply/test.yaml
  '

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Starting S3 manifest backup..."
}

@test "backup_templates: shows bucket name when calling s3" {
  export MANIFEST_BACKUP='{"ENABLED":"true","TYPE":"s3","BUCKET":"my-bucket","PREFIX":"backups"}'

  aws() {
    return 0
  }
  export -f aws
  export REGION="us-east-1"

  run bash -c '
    source "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/output/123/apply/test.yaml
  '

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Bucket: my-bucket"
}

@test "backup_templates: shows prefix when calling s3" {
  export MANIFEST_BACKUP='{"ENABLED":"true","TYPE":"s3","BUCKET":"my-bucket","PREFIX":"backups"}'

  aws() {
    return 0
  }
  export -f aws
  export REGION="us-east-1"

  run bash -c '
    source "$SERVICE_PATH/backup/backup_templates" --action=apply --files /tmp/output/123/apply/test.yaml
  '

  assert_equal "$status" "0"
  assert_contains "$output" "📋 Prefix: backups"
}
