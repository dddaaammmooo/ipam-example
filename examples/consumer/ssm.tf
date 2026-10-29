# Publish each VPC's allocation to SSM Parameter Store in the AWS account
# that runs that product in that environment. Application stacks then read
# their network layout from their own account instead of from the IPAM repo:
#
#   data "aws_ssm_parameter" "vpc_cidr" { name = "/platform/network/vpc/cidr" }
#
# Parameters written in each account (prefix = var.ssm_prefix):
#
#   <prefix>/vpc/cidr                 String      10.4.0.0/14
#   <prefix>/vpc/cidr-blocks          StringList  10.4.0.0/16,10.5.0.0/16,...  (AWS-sized pieces; first = primary)
#   <prefix>/subnets/<tier>/cidrs     StringList  one CIDR per AZ, same order as .../azs
#   <prefix>/subnets/<tier>/azs       StringList  eu-west-1a,eu-west-1b,eu-west-1c
#   <prefix>/allocation               String      JSON with all of the above plus IPAM ids
#
# One AWS provider per account, each assuming var.ssm_publisher_role_name.
# Keys are "<product>-<env>", the same keys as github-ipam_allocation.vpc.

locals {
  ssm_targets = var.publish_to_ssm ? local.vpcs : {}

  # "<vpc key>" => { compute = [subnet keys in AZ order], data = [...], ... }
  vpc_tiers = {
    for vpc_key, v in local.vpcs : vpc_key => {
      for tier in keys(local.catalogue[v.product].subnets) :
      tier => [for az in var.azs : "${vpc_key}-${tier}-${az}"]
    }
  }

  ssm_documents = {
    for vpc_key, v in local.ssm_targets : vpc_key => {
      product         = v.product
      environment     = v.env
      account_id      = v.account
      region          = var.aws_region
      vpc_cidr        = github-ipam_allocation.vpc[vpc_key].cidr
      vpc_cidr_blocks = local.aws_vpc_cidr_blocks[vpc_key]
      ipam_id         = github-ipam_allocation.vpc[vpc_key].id
      subnets = {
        for tier, subnet_keys in local.vpc_tiers[vpc_key] : tier => {
          for i, k in subnet_keys : var.azs[i] => {
            cidr    = github-ipam_allocation.subnet[k].cidr
            ipam_id = github-ipam_allocation.subnet[k].id
          }
        }
      }
    }
  }

  # Flatten to one entry per parameter: "<vpc key>|<path>" => { vpc, path, type, value }
  ssm_parameters = merge([
    for vpc_key, doc in local.ssm_documents : merge(
      {
        "${vpc_key}|vpc/cidr"        = { vpc = vpc_key, path = "vpc/cidr", type = "String", value = doc.vpc_cidr }
        "${vpc_key}|vpc/cidr-blocks" = { vpc = vpc_key, path = "vpc/cidr-blocks", type = "StringList", value = join(",", doc.vpc_cidr_blocks) }
        "${vpc_key}|allocation"      = { vpc = vpc_key, path = "allocation", type = "String", value = jsonencode(doc) }
      },
      merge([
        for tier, by_az in doc.subnets : {
          "${vpc_key}|subnets/${tier}/cidrs" = { vpc = vpc_key, path = "subnets/${tier}/cidrs", type = "StringList", value = join(",", [for az in var.azs : by_az[az].cidr]) }
          "${vpc_key}|subnets/${tier}/azs"   = { vpc = vpc_key, path = "subnets/${tier}/azs", type = "StringList", value = join(",", var.azs) }
        }
      ]...)
    )
  ]...)
}

provider "aws" {
  alias    = "app"
  for_each = local.ssm_targets

  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${each.value.account}:role/${var.ssm_publisher_role_name}"
    session_name = "ipam-ssm-publisher"
  }

  # Refuse to write if the role somehow lands in a different account.
  allowed_account_ids = [each.value.account]

  default_tags {
    tags = {
      ManagedBy   = "ipam-example/examples/consumer"
      Product     = each.value.product
      Environment = each.value.env
    }
  }
}

resource "aws_ssm_parameter" "network" {
  for_each = local.ssm_parameters
  provider = aws.app[each.value.vpc]

  name        = "${var.ssm_prefix}/${each.value.path}"
  type        = each.value.type
  value       = each.value.value
  description = "Allocated by github-ipam (dddaaammmooo/ipam-example); do not edit by hand."
}
