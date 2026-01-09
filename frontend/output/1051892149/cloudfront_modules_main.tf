resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "${var.distribution_app_name}-oac"
  description                       = "OAC for ${var.distribution_app_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "static" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = local.distribution_aliases
  price_class         = "PriceClass_100"
  comment             = "Distribution for ${var.distribution_app_name}"

  origin {
    domain_name              = data.aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = local.distribution_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id

    origin_path              = var.distribution_s3_prefix != "" ? "/${var.distribution_s3_prefix}" : ""
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.distribution_origin_id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  ordered_cache_behavior {
    path_pattern     = "/static/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.distribution_origin_id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 86400
    default_ttl            = 604800
    max_ttl                = 31536000
    compress               = true
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = local.distribution_default_tags
}
