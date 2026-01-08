data "aws_route53_zone" "public" {
  name = var.domain
}

resource "aws_amplify_app" "app" {
  name = var.application_name
  repository = var.repository_url

  oauth_token = var.github_token

  enable_branch_auto_build = false
  enable_branch_auto_deletion = false
  enable_auto_branch_creation = false

  build_spec = <<EOF
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: dist
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}

resource "aws_amplify_branch" "tag" {
  app_id = aws_amplify_app.app.id
  branch_name = local.git_ref

  stage = "PRODUCTION"
  enable_auto_build = true

  environment_variables = local.env_vars

  tags = local.resource_tags
}

# Use CNAME record pointing to the Amplify-generated domain
resource "aws_route53_record" "amplify" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "${var.subdomain}.${var.domain}"
  type    = "CNAME"
  ttl     = 300

  records = [aws_amplify_app.app.default_domain]
}

resource "aws_amplify_domain_association" "domain_association" {
  app_id = aws_amplify_app.app.id
  domain_name = var.domain

  # Wait for domain verification to complete (can take 5-15 minutes)
  wait_for_verification = true

  sub_domain {
    branch_name = aws_amplify_branch.tag.branch_name
    prefix      = var.subdomain
  }

  depends_on = [aws_route53_record.amplify]
}

resource "null_resource" "trigger_build" {
  triggers = {
    branch_id = aws_amplify_branch.tag.id
    commit_id = var.application_version
    # Force rebuild when environment variables change
    env_vars_hash = md5(var.env_vars_json)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Start the build job
      JOB_ID=$(aws amplify start-job \
        --app-id ${aws_amplify_app.app.id} \
        --branch-name ${aws_amplify_branch.tag.branch_name} \
        --job-type RELEASE \
        --query 'jobSummary.jobId' \
        --output text)

      echo "Started Amplify build job: $JOB_ID"

      # Wait for the job to complete
      while true; do
        STATUS=$(aws amplify get-job \
          --app-id ${aws_amplify_app.app.id} \
          --branch-name ${aws_amplify_branch.tag.branch_name} \
          --job-id $JOB_ID \
          --query 'job.summary.status' \
          --output text)

        echo "Build status: $STATUS"

        if [ "$STATUS" = "SUCCEED" ]; then
          echo "Build completed successfully!"
          break
        elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "CANCELLED" ]; then
          echo "Build failed with status: $STATUS"
          exit 1
        fi

        sleep 10
      done
    EOT
  }

  depends_on = [aws_amplify_branch.tag]
}