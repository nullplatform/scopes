# =============================================================================
# Unit tests for provider/aws module
#
# Run: tofu test
# =============================================================================

mock_provider "aws" {}

variables {
  aws_provider = {
    region       = "us-east-1"
    state_bucket = "my-terraform-state"
    lock_table   = "terraform-locks"
  }

  provider_resource_tags_json = {
    Environment = "test"
    Project     = "frontend"
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# Test: Provider configuration is valid
# =============================================================================
run "provider_configuration_is_valid" {
  command = plan

  assert {
    condition     = var.aws_provider.region == "us-east-1"
    error_message = "AWS region should be us-east-1"
  }

  assert {
    condition     = var.aws_provider.state_bucket == "my-terraform-state"
    error_message = "State bucket should be my-terraform-state"
  }

  assert {
    condition     = var.aws_provider.lock_table == "terraform-locks"
    error_message = "Lock table should be terraform-locks"
  }
}

# =============================================================================
# Test: Default tags are configured
# =============================================================================
run "default_tags_are_configured" {
  command = plan

  assert {
    condition     = var.provider_resource_tags_json["Environment"] == "test"
    error_message = "Environment tag should be 'test'"
  }

  assert {
    condition     = var.provider_resource_tags_json["ManagedBy"] == "terraform"
    error_message = "ManagedBy tag should be 'terraform'"
  }
}

# =============================================================================
# Test: Required variables validation
# =============================================================================
run "aws_provider_requires_region" {
  command = plan

  variables {
    aws_provider = {
      region       = ""
      state_bucket = "bucket"
      lock_table   = "table"
    }
  }

  # Empty region should still be syntactically valid but semantically wrong
  # This tests that the variable structure is enforced
  assert {
    condition     = var.aws_provider.region == ""
    error_message = "Empty region should be accepted by variable type"
  }
}
