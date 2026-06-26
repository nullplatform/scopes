################################################################################
# IAM permissions role assumed by the nullplatform agent role
#
# Holds the actual workload policies (Route53, EKS, ELB). Its trust policy
# trusts only the agent IRSA role (plus any additional roles), so an agent's IRSA
# token cannot exercise these permissions without first assuming it (sts:AssumeRole).
#
# This is the "permissions role" half of the reference module
# tofu-modules/infrastructure/aws/iam/agent. The IRSA agent role itself is
# created once at cluster setup and is out of scope for this module.
################################################################################

resource "aws_iam_role" "nullplatform_agent_permissions" {
  count = local.iam_create ? 1 : 0

  name        = local.permissions_role_name
  description = "Permissions role assumed by the nullplatform agent role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = concat([local.agent_role_arn], var.additional_agent_role_arns) }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.iam_default_tags
}

################################################################################
# Policy attachments
################################################################################

resource "aws_iam_role_policy_attachment" "permissions_route53" {
  count = local.iam_create ? 1 : 0

  role       = aws_iam_role.nullplatform_agent_permissions[0].name
  policy_arn = aws_iam_policy.nullplatform_route53_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "permissions_eks" {
  count = local.iam_create ? 1 : 0

  role       = aws_iam_role.nullplatform_agent_permissions[0].name
  policy_arn = aws_iam_policy.nullplatform_eks_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "permissions_elb" {
  count = local.iam_create ? 1 : 0

  role       = aws_iam_role.nullplatform_agent_permissions[0].name
  policy_arn = aws_iam_policy.nullplatform_elb_policy[0].arn
}

################################################################################
# Route 53 IAM policy
# Manage Route 53 DNS records for service discovery.
################################################################################

resource "aws_iam_policy" "nullplatform_route53_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}_route53_policy"
  description = "Policy for managing Route 53 DNS records"
  tags        = local.iam_default_tags
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName"
        ],
        "Resource" : [
          "arn:aws:route53:::hostedzone/*"
        ],
      }
    ]
  })
}

################################################################################
# Elastic Load Balancing (ELB) IAM policy
# Describe and monitor load balancers and target groups.
################################################################################

resource "aws_iam_policy" "nullplatform_elb_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}_elb_policy"
  description = "Policy for managing Elastic Load Balancing resources"
  tags        = local.iam_default_tags
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "elasticloadbalancing:DescribeLoadBalancers",
            "elasticloadbalancing:DescribeTargetGroups"
          ],
          "Resource" : "*",
          "Condition" : {
            "StringEquals" : {
              "aws:RequestedRegion" : [
                data.aws_region.current.region
              ]
            }
          }
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "elasticloadbalancing:DescribeTargetHealth",
            "elasticloadbalancing:DescribeListeners",
            "elasticloadbalancing:DescribeRules"
          ],
          "Resource" : [
            "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/k8s-nullplatform-*",
            "arn:aws:elasticloadbalancing:*:*:targetgroup/k8s-nullplatform-*"
          ],
        }
      ]
    }
  )
}

################################################################################
# EKS IAM policy
# Describe and list EKS cluster resources.
################################################################################

resource "aws_iam_policy" "nullplatform_eks_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}_eks_policy"
  description = "Policy for managing EKS cluster resources"
  tags        = local.iam_default_tags
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:DescribeAddon",
          "eks:ListAddons"
        ],
        "Resource" : [
          "arn:aws:eks:*:*:cluster/*",
          "arn:aws:eks:*:*:nodegroup/*",
          "arn:aws:eks:*:*:addon/*"
        ],
      }
    ]
  })
}
