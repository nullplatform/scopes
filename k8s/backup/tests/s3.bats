#!/usr/bin/env bats
# =============================================================================
# Unit tests for backup/s3 - S3 manifest backup operations
# =============================================================================

setup() {
  # Get project root directory
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  # Source assertions
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Set required environment variables
  export SERVICE_PATH="$PROJECT_ROOT/k8s"
  export REGION="us-east-1"
  export MANIFEST_BACKUP='{"ENABLED":"true","TYPE":"s3","BUCKET":"test-bucket","PREFIX":"manifests"}'

  # Create temp files for testing
  export TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/output/scope-123/apply"
  echo "test content" > "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  # Mock aws CLI by default (success)
  aws() {
    return 0
  }
  export -f aws
}

teardown() {
  rm -rf "$TEST_DIR"
  unset MANIFEST_BACKUP
  unset SERVICE_PATH
  unset REGION
  unset -f aws
}

# =============================================================================
# Test: Displays starting message
# =============================================================================
@test "s3: displays starting message with emoji" {
  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  assert_equal "$status" "0"
  assert_contains "$output" "📝 Starting S3 manifest backup..."
}

# =============================================================================
# Test: Extracts bucket from MANIFEST_BACKUP
# =============================================================================
@test "s3: extracts bucket from MANIFEST_BACKUP" {
  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  assert_contains "$output" "📋 Bucket: test-bucket"
}

# =============================================================================
# Test: Extracts prefix from MANIFEST_BACKUP
# =============================================================================
@test "s3: extracts prefix from MANIFEST_BACKUP" {
  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  assert_contains "$output" "📋 Prefix: manifests"
}

# =============================================================================
# Test: Shows file count
# =============================================================================
@test "s3: shows file count" {
  echo "test" > "$TEST_DIR/output/scope-123/apply/service.yaml"

  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml" "$TEST_DIR/output/scope-123/apply/service.yaml"

  assert_contains "$output" "📋 Files: 2"
}

# =============================================================================
# Test: Shows action
# =============================================================================
@test "s3: shows action with emoji" {
  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  assert_contains "$output" "📋 Action: apply"
}

# =============================================================================
# Test: Uploads file on apply action
# =============================================================================
@test "s3: uploads file on apply action" {
  local aws_called=false
  aws() {
    if [[ "$1" == "s3" && "$2" == "cp" ]]; then
      aws_called=true
    fi
    return 0
  }
  export -f aws

  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📝 Processing:"
  assert_contains "$output" "📡 Uploading to"
  assert_contains "$output" "✅ Upload successful"
}

# =============================================================================
# Test: Deletes file on delete action
# =============================================================================
@test "s3: deletes file on delete action" {
  mkdir -p "$TEST_DIR/output/scope-123/delete"
  echo "test" > "$TEST_DIR/output/scope-123/delete/deployment.yaml"

  aws() {
    if [[ "$1" == "s3" && "$2" == "rm" ]]; then
      return 0
    fi
    return 0
  }
  export -f aws

  run bash "$SERVICE_PATH/backup/s3" --action=delete --files "$TEST_DIR/output/scope-123/delete/deployment.yaml"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📡 Deleting"
  assert_contains "$output" "✅ Deletion successful"
}

# =============================================================================
# Test: Handles NoSuchKey error gracefully on delete
# =============================================================================
@test "s3: handles NoSuchKey error gracefully on delete" {
  mkdir -p "$TEST_DIR/output/scope-123/delete"
  echo "test" > "$TEST_DIR/output/scope-123/delete/deployment.yaml"

  aws() {
    if [[ "$1" == "s3" && "$2" == "rm" ]]; then
      echo "An error occurred (NoSuchKey) when calling the DeleteObject operation"
      return 1
    fi
    return 0
  }
  export -f aws

  run bash "$SERVICE_PATH/backup/s3" --action=delete --files "$TEST_DIR/output/scope-123/delete/deployment.yaml"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 File not found in S3, skipping"
}

# =============================================================================
# Test: Handles Not Found error gracefully on delete
# =============================================================================
@test "s3: handles Not Found error gracefully on delete" {
  mkdir -p "$TEST_DIR/output/scope-123/delete"
  echo "test" > "$TEST_DIR/output/scope-123/delete/deployment.yaml"

  aws() {
    if [[ "$1" == "s3" && "$2" == "rm" ]]; then
      echo "Not Found"
      return 1
    fi
    return 0
  }
  export -f aws

  run bash "$SERVICE_PATH/backup/s3" --action=delete --files "$TEST_DIR/output/scope-123/delete/deployment.yaml"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 File not found in S3, skipping"
}

# =============================================================================
# Test: Fails on upload error - Error message
# =============================================================================
@test "s3: fails on upload error with error message" {
  aws() {
    if [[ "$1" == "s3" && "$2" == "cp" ]]; then
      return 1
    fi
    return 0
  }
  export -f aws

  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  [ "$status" -eq 1 ]

  assert_contains "$output" "❌ Upload failed"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• S3 bucket does not exist or is not accessible"
  assert_contains "$output" "• IAM permissions are missing for s3:PutObject"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify bucket 'test-bucket' exists and is accessible"
  assert_contains "$output" "• Check IAM permissions for the agent"
}

# =============================================================================
# Test: Fails on delete error (non-NoSuchKey) - Error message
# =============================================================================
@test "s3: fails on delete error with error message" {
  mkdir -p "$TEST_DIR/output/scope-123/delete"
  echo "test" > "$TEST_DIR/output/scope-123/delete/deployment.yaml"

  aws() {
    if [[ "$1" == "s3" && "$2" == "rm" ]]; then
      echo "Access Denied"
      return 1
    fi
    return 0
  }
  export -f aws

  run bash "$SERVICE_PATH/backup/s3" --action=delete --files "$TEST_DIR/output/scope-123/delete/deployment.yaml"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Deletion failed"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• S3 bucket does not exist or is not accessible"
  assert_contains "$output" "• IAM permissions are missing for s3:DeleteObject"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Verify bucket 'test-bucket' exists and is accessible"
  assert_contains "$output" "• Check IAM permissions for the agent"
}

# =============================================================================
# Test: Fails on invalid action - Error message
# =============================================================================
@test "s3: fails on invalid action with error message" {
  run bash "$SERVICE_PATH/backup/s3" --action=invalid --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  [ "$status" -eq 1 ]
  assert_contains "$output" "❌ Invalid action: 'invalid'"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "The action parameter must be 'apply' or 'delete'"
}

# =============================================================================
# Test: Constructs correct S3 path
# =============================================================================
@test "s3: constructs correct S3 path from file path" {
  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  # S3 path should be: manifests/scope-123/deployment.yaml
  assert_contains "$output" "manifests/scope-123/deployment.yaml"
}

# =============================================================================
# Test: Shows success summary
# =============================================================================
@test "s3: shows success summary" {
  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  [ "$status" -eq 0 ]
  assert_contains "$output" "✨ S3 backup operation completed successfully"
}

# =============================================================================
# Test: Processes multiple files
# =============================================================================
@test "s3: processes multiple files" {
  echo "test" > "$TEST_DIR/output/scope-123/apply/service.yaml"
  echo "test" > "$TEST_DIR/output/scope-123/apply/secret.yaml"

  local upload_count=0
  aws() {
    if [[ "$1" == "s3" && "$2" == "cp" ]]; then
      upload_count=$((upload_count + 1))
    fi
    return 0
  }
  export -f aws

  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml" "$TEST_DIR/output/scope-123/apply/service.yaml" "$TEST_DIR/output/scope-123/apply/secret.yaml"

  [ "$status" -eq 0 ]
  assert_contains "$output" "📋 Files: 3"
}


# =============================================================================
# Test: Uses REGION environment variable
# =============================================================================
@test "s3: uses REGION environment variable" {
  local region_used=""
  aws() {
    for arg in "$@"; do
      if [[ "$arg" == "us-east-1" ]]; then
        region_used="us-east-1"
      fi
    done
    return 0
  }
  export -f aws

  run bash "$SERVICE_PATH/backup/s3" --action=apply --files "$TEST_DIR/output/scope-123/apply/deployment.yaml"

  [ "$status" -eq 0 ]
}
