# =============================================================================
# Unit tests for distribution/cloudfront module
#
# Run: tofu test
# =============================================================================

mock_provider "aws" {
  mock_data "aws_s3_bucket" {
    defaults = {
      id                          = "my-static-bucket"
      arn                         = "arn:aws:s3:::my-static-bucket"
      bucket_regional_domain_name = "my-static-bucket.s3.us-east-1.amazonaws.com"
    }
  }
}

variables {
  distribution_bucket_name       = "my-static-bucket"
  distribution_s3_prefix         = "app/scope-1"
  distribution_app_name          = "my-app-prod"
  distribution_custom_domain     = null
  distribution_resource_tags_json = {
    Environment = "production"
    Application = "my-app"
  }
}

# =============================================================================
# Test: Origin Access Control is created
# =============================================================================
run "creates_origin_access_control" {
  command = plan

  assert {
    condition     = aws_cloudfront_origin_access_control.static.name == "my-app-prod-oac"
    error_message = "OAC name should be 'my-app-prod-oac'"
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.static.origin_access_control_origin_type == "s3"
    error_message = "OAC origin type should be 's3'"
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.static.signing_behavior == "always"
    error_message = "OAC signing behavior should be 'always'"
  }
}

# =============================================================================
# Test: CloudFront distribution basic configuration
# =============================================================================
run "distribution_basic_configuration" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.static.enabled == true
    error_message = "Distribution should be enabled"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.is_ipv6_enabled == true
    error_message = "IPv6 should be enabled"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_root_object == "index.html"
    error_message = "Default root object should be 'index.html'"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.price_class == "PriceClass_100"
    error_message = "Price class should be 'PriceClass_100'"
  }
}

# =============================================================================
# Test: Distribution has no aliases when custom domain is null
# =============================================================================
run "no_aliases_without_custom_domain" {
  command = plan

  assert {
    condition     = length(local.distribution_aliases) == 0
    error_message = "Should have no aliases when custom_domain is null"
  }
}

# =============================================================================
# Test: Distribution has alias when custom domain is set
# =============================================================================
run "has_alias_with_custom_domain" {
  command = plan

  variables {
    distribution_custom_domain = "cdn.example.com"
  }

  assert {
    condition     = length(local.distribution_aliases) == 1
    error_message = "Should have one alias when custom_domain is set"
  }

  assert {
    condition     = local.distribution_aliases[0] == "cdn.example.com"
    error_message = "Alias should be 'cdn.example.com'"
  }
}

# =============================================================================
# Test: Origin ID is computed correctly
# =============================================================================
run "origin_id_format" {
  command = plan

  assert {
    condition     = local.distribution_origin_id == "S3-my-static-bucket"
    error_message = "Origin ID should be 'S3-my-static-bucket'"
  }
}

# =============================================================================
# Test: Default tags include module tag
# =============================================================================
run "default_tags_include_module" {
  command = plan

  assert {
    condition     = local.distribution_default_tags["ManagedBy"] == "terraform"
    error_message = "Tags should include ManagedBy=terraform"
  }

  assert {
    condition     = local.distribution_default_tags["Module"] == "distribution/cloudfront"
    error_message = "Tags should include Module=distribution/cloudfront"
  }

  assert {
    condition     = local.distribution_default_tags["Environment"] == "production"
    error_message = "Tags should preserve input Environment tag"
  }
}

# =============================================================================
# Test: Cross-module locals for DNS integration
# =============================================================================
run "cross_module_locals_for_dns" {
  command = plan

  assert {
    condition     = local.distribution_record_type == "A"
    error_message = "Record type should be 'A' for CloudFront alias records"
  }
}

# =============================================================================
# Test: Cache behaviors
# =============================================================================
run "cache_behaviors_configured" {
  command = plan

  # Default cache behavior
  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Default cache should redirect to HTTPS"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].compress == true
    error_message = "Default cache should enable compression"
  }
}

# =============================================================================
# Test: Custom error responses for SPA
# =============================================================================
run "spa_error_responses" {
  command = plan

  # Check that 404 and 403 errors redirect to index.html (SPA behavior)
  assert {
    condition     = length(aws_cloudfront_distribution.static.custom_error_response) == 2
    error_message = "Should have 2 custom error responses"
  }
}

# =============================================================================
# Test: Outputs from data source
# =============================================================================
run "outputs_from_data_source" {
  command = plan

  assert {
    condition     = output.distribution_bucket_name == "my-static-bucket"
    error_message = "distribution_bucket_name should be 'my-static-bucket'"
  }

  assert {
    condition     = output.distribution_bucket_arn == "arn:aws:s3:::my-static-bucket"
    error_message = "distribution_bucket_arn should be 'arn:aws:s3:::my-static-bucket'"
  }
}

# =============================================================================
# Test: Outputs from variables
# =============================================================================
run "outputs_from_variables" {
  command = plan

  assert {
    condition     = output.distribution_s3_prefix == "app/scope-1"
    error_message = "distribution_s3_prefix should be 'app/scope-1'"
  }
}

# =============================================================================
# Test: DNS-related outputs
# =============================================================================
run "dns_related_outputs" {
  command = plan

  assert {
    condition     = output.distribution_record_type == "A"
    error_message = "distribution_record_type should be 'A'"
  }
}

# =============================================================================
# Test: Website URL without custom domain
# =============================================================================
run "website_url_without_custom_domain" {
  command = plan

  # Without custom domain, URL should use CloudFront domain (known after apply)
  # We can only check it starts with https://
  assert {
    condition     = startswith(output.distribution_website_url, "https://")
    error_message = "distribution_website_url should start with 'https://'"
  }
}

# =============================================================================
# Test: Website URL with custom domain
# =============================================================================
run "website_url_with_custom_domain" {
  command = plan

  variables {
    distribution_custom_domain = "cdn.example.com"
  }

  assert {
    condition     = output.distribution_website_url == "https://cdn.example.com"
    error_message = "distribution_website_url should be 'https://cdn.example.com'"
  }
}
