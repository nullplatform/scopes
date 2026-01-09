resource "aws_route53_record" "main_alias" {
  count = local.hosting_record_type == "A" ? 1 : 0

  zone_id = var.network_hosted_zone_id
  name    = local.network_full_domain
  type    = "A"

  alias {
    name                   = local.hosting_target_domain
    zone_id                = local.hosting_target_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "main_cname" {
  count = local.hosting_record_type == "CNAME" ? 1 : 0

  zone_id = var.network_hosted_zone_id
  name    = local.network_full_domain
  type    = "CNAME"
  ttl     = 300
  records = [local.hosting_target_domain]
}
