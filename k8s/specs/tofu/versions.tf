terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # v6+ required: the ELB policy reads data.aws_region.current.region,
      # which replaced the v5 `.name` attribute.
      version = ">= 6.0"
    }
  }
}
