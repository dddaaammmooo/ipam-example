terraform {
  required_version = ">= 1.6"

  required_providers {
    github-ipam = {
      source  = "easytofu/github-ipam"
      version = "~> 0.0.21"
    }
  }
}
