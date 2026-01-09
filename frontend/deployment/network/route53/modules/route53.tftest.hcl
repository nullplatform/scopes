# =============================================================================
# Unit tests for network/route53 module
#
# Run: tofu test
# =============================================================================

mock_provider "aws" {}

variables {
  network_hosted_zone_id = "Z1234567890ABC"
  network_domain         = "example.com"
  network_subdomain      = "app"

  # These come from the distribution module (e.g., cloudfront)
  distribution_target_domain  = "d1234567890.cloudfront.net"
  distribution_target_zone_id = "Z2FDTNDATAQYW2"
  distribution_record_type    = "A"
}

# =============================================================================
# Test: Full domain is computed correctly with subdomain
# =============================================================================
run "full_domain_with_subdomain" {
  command = plan

  assert {
    condition     = local.network_full_domain == "app.example.com"
    error_message = "Full domain should be 'app.example.com', got '${local.network_full_domain}'"
  }
}

# =============================================================================
# Test: Full domain is computed correctly without subdomain (apex)
# =============================================================================
run "full_domain_apex" {
  command = plan

  variables {
    network_subdomain = ""
  }

  assert {
    condition     = local.network_full_domain == "example.com"
    error_message = "Full domain should be 'example.com' for apex, got '${local.network_full_domain}'"
  }
}

# =============================================================================
# Test: A record is created for alias type
# =============================================================================
run "creates_alias_record_for_type_a" {
  command = plan

  variables {
    distribution_record_type = "A"
  }

  assert {
    condition     = length(aws_route53_record.main_alias) == 1
    error_message = "Should create one A alias record"
  }

  assert {
    condition     = length(aws_route53_record.main_cname) == 0
    error_message = "Should not create CNAME record when type is A"
  }
}

# =============================================================================
# Test: CNAME record is created for CNAME type
# =============================================================================
run "creates_cname_record_for_type_cname" {
  command = plan

  variables {
    distribution_record_type = "CNAME"
  }

  assert {
    condition     = length(aws_route53_record.main_cname) == 1
    error_message = "Should create one CNAME record"
  }

  assert {
    condition     = length(aws_route53_record.main_alias) == 0
    error_message = "Should not create A alias record when type is CNAME"
  }
}

# =============================================================================
# Test: A record configuration
# =============================================================================
run "alias_record_configuration" {
  command = plan

  variables {
    distribution_record_type = "A"
  }

  assert {
    condition     = aws_route53_record.main_alias[0].zone_id == "Z1234567890ABC"
    error_message = "Record should use the correct hosted zone ID"
  }

  assert {
    condition     = aws_route53_record.main_alias[0].type == "A"
    error_message = "Record type should be A"
  }

  assert {
    condition     = aws_route53_record.main_alias[0].name == "app.example.com"
    error_message = "Record name should be the full domain"
  }
}

# =============================================================================
# Test: CNAME record configuration
# =============================================================================
run "cname_record_configuration" {
  command = plan

  variables {
    distribution_record_type = "CNAME"
  }

  assert {
    condition     = aws_route53_record.main_cname[0].zone_id == "Z1234567890ABC"
    error_message = "Record should use the correct hosted zone ID"
  }

  assert {
    condition     = aws_route53_record.main_cname[0].type == "CNAME"
    error_message = "Record type should be CNAME"
  }

  assert {
    condition     = aws_route53_record.main_cname[0].ttl == 300
    error_message = "CNAME TTL should be 300"
  }
}

# =============================================================================
# Test: Outputs
# =============================================================================
run "outputs_are_correct" {
  command = plan

  assert {
    condition     = output.network_full_domain == "app.example.com"
    error_message = "network_full_domain output should be 'app.example.com'"
  }

  assert {
    condition     = output.network_website_url == "https://app.example.com"
    error_message = "network_website_url output should be 'https://app.example.com'"
  }
}
