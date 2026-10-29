# 20 products x 3 environments = 60 VPCs, each split into compute / data /
# public subnets across 3 AZs. Sizes live in products.yaml, so adding a
# product or resizing one is a data change, not a code change.
#
# Every CIDR is recorded in config/allocations.yaml of the IPAM repo, so
# no two VPCs (or subnets) anywhere can overlap.

locals {
  catalogue = yamldecode(file("${path.module}/products.yaml")).products

  # "media-streaming-prd" => { product, env, pool, mask, ... }
  vpcs = merge([
    for product, p in local.catalogue : {
      for env in var.environments : "${product}-${env}" => {
        product = product
        env     = env
        pool    = p.pools[env]
        mask    = p.vpc[env]
        size    = p.size
        team    = p.team
        account = p.accounts[env]
      }
    }
  ]...)

  # "media-streaming-prd-compute-eu-west-1a" => { vpc, tier, az, mask }
  subnets = merge([
    for vpc_key, v in local.vpcs : merge([
      for tier, masks in local.catalogue[v.product].subnets : {
        for az in var.azs : "${vpc_key}-${tier}-${az}" => {
          vpc  = vpc_key
          tier = tier
          az   = az
          mask = masks[v.env]
        }
      }
    ]...)
  ]...)
}

# Mode 1 (pool_id): one VPC block per product per environment.
resource "github-ipam_allocation" "vpc" {
  for_each = local.vpcs

  pool_id   = each.value.pool
  cidr_mask = each.value.mask
  name      = "${each.key}-vpc"

  metadata = {
    product     = each.value.product
    environment = each.value.env
    size        = each.value.size
    team        = each.value.team
  }
}

# Mode 2 (parent_cidr): subnets carved out of their VPC block. Each VPC is
# sized with headroom, so subnets fit whatever order Terraform creates them
# in (the provider aligns every block to its own boundary).
resource "github-ipam_allocation" "subnet" {
  for_each = local.subnets

  parent_cidr = github-ipam_allocation.vpc[each.value.vpc].cidr
  cidr_mask   = each.value.mask
  name        = each.key

  metadata = {
    tier = each.value.tier
    az   = each.value.az
  }
}

# AWS caps a VPC CIDR block at /16. Bigger blocks (the /14 and /15
# products) are attached as consecutive /16s: the first as the VPC's
# primary CIDR, the rest as secondary associations (default quota: 5 per
# VPC, so a /14 = 4 x /16 fits).
locals {
  vpc_prefix = { for k, a in github-ipam_allocation.vpc : k => tonumber(split("/", a.cidr)[1]) }

  aws_vpc_cidr_blocks = {
    for k, a in github-ipam_allocation.vpc : k => (
      local.vpc_prefix[k] < 16
      ? cidrsubnets(a.cidr, [for i in range(pow(2, 16 - local.vpc_prefix[k])) : 16 - local.vpc_prefix[k]]...)
      : [a.cidr]
    )
  }
}

# Wiring into AWS (commented out so the example runs with only a GitHub
# token):
#
# resource "aws_vpc" "this" {
#   for_each   = local.aws_vpc_cidr_blocks
#   cidr_block = each.value[0]
#   tags       = { Name = each.key, Product = local.vpcs[each.key].product, Env = local.vpcs[each.key].env }
# }
#
# resource "aws_vpc_ipv4_cidr_block_association" "extra" {
#   for_each = merge([for k, blocks in local.aws_vpc_cidr_blocks :
#     { for i, c in slice(blocks, 1, length(blocks)) : "${k}-${i + 1}" => { vpc = k, cidr = c } }
#   ]...)
#   vpc_id     = aws_vpc.this[each.value.vpc].id
#   cidr_block = each.value.cidr
# }
#
# resource "aws_subnet" "this" {
#   for_each          = github-ipam_allocation.subnet
#   vpc_id            = aws_vpc.this[local.subnets[each.key].vpc].id
#   cidr_block        = each.value.cidr
#   availability_zone = local.subnets[each.key].az
#   tags              = { Name = each.key, Tier = local.subnets[each.key].tier }
#   depends_on        = [aws_vpc_ipv4_cidr_block_association.extra]
# }
