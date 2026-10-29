terraform {
  # OpenTofu >= 1.9 for `for_each` on provider blocks (one AWS provider per
  # application account in ssm.tf). Terraform does not support this; see
  # the README for the per-account alternative.
  required_version = ">= 1.9"

  required_providers {
    github-ipam = {
      source  = "easytofu/github-ipam"
      version = "~> 0.0.21"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
