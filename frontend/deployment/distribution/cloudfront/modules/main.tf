resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "${var.distribution_app_name}-oac"
  description                       = "OAC for ${var.distribution_app_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "static" {
  bucket = data.aws_s3_bucket.static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${data.aws_s3_bucket.static.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.static.id}"
          }
        }
      }
    ]
  })
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

    origin_path              = local.distribution_origin_path
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

  # Use ACM certificate if available for custom domain, otherwise use default CloudFront certificate
  dynamic "viewer_certificate" {
    for_each = local.distribution_has_acm_certificate ? [1] : []
    content {
      acm_certificate_arn      = data.aws_acm_certificate.custom_domain[0].arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.distribution_has_acm_certificate ? [] : [1]
    content {
      cloudfront_default_certificate = true
      minimum_protocol_version       = "TLSv1.2_2021"
    }
  }

  tags = local.distribution_default_tags
}

# Invalidate CloudFront cache on every deployment (when origin path changes)
resource "terraform_data" "cloudfront_invalidation" {
  # Trigger invalidation whenever the origin path changes
  triggers_replace = [
    local.distribution_origin_path
  ]

  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation ${local.distribution_aws_endpoint_url_param} --distribution-id ${aws_cloudfront_distribution.static.id} --paths '/*'"
  }

  depends_on = [aws_cloudfront_distribution.static]
}