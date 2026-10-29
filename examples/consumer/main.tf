# A typical consumer: one VPC-sized block from a pool, then subnets carved
# out of it. The CIDRs are recorded in config/allocations.yaml, so the next
# team that asks gets a block that cannot overlap this one.

data "github-ipam_pool" "this" {
  pool_id = var.pool_id
}

# Mode 1 (pool_id): take the next free /16 from the pool.
resource "github-ipam_allocation" "vpc" {
  pool_id   = data.github-ipam_pool.this.pool_id
  cidr_mask = 16
  name      = "${var.name}-vpc"

  metadata = {
    purpose     = "vpc"
    environment = data.github-ipam_pool.this.metadata["environment"]
    managed_by  = "examples/consumer"
  }
}

# Hold the /16 right after the VPC so a secondary CIDR can be attached
# later and still be contiguous (handy for route summarisation).
resource "github-ipam_allocation" "vpc_growth" {
  pool_id         = data.github-ipam_pool.this.pool_id
  cidr_mask       = 16
  name            = "${var.name}-vpc-growth"
  status          = "reservation"
  contiguous_with = github-ipam_allocation.vpc.cidr

  metadata = {
    purpose = "future secondary CIDR for ${var.name}-vpc"
  }
}

locals {
  # Subnet sizes per tier. /20 private = 4,096 addresses per AZ for pods
  # and instances; /24 public and data are plenty for load balancers and
  # databases.
  tiers = {
    private = 20
    public  = 24
    data    = 24
  }

  subnets = {
    for pair in setproduct(keys(local.tiers), var.azs) :
    "${pair[0]}-${pair[1]}" => { tier = pair[0], az = pair[1], mask = local.tiers[pair[0]] }
  }
}

# Mode 2 (parent_cidr): carve subnets out of the VPC allocation. The
# provider aligns each block to its own boundary, so mixed sizes are safe.
resource "github-ipam_allocation" "subnet" {
  for_each = local.subnets

  parent_cidr = github-ipam_allocation.vpc.cidr
  cidr_mask   = each.value.mask
  name        = "${var.name}-${each.key}"

  metadata = {
    tier = each.value.tier
    az   = each.value.az
  }
}

# Read-only lookups, e.g. for a dashboard or a firewall rule generator.
data "github-ipam_allocations" "in_vpc" {
  parent_cidr = github-ipam_allocation.vpc.cidr
  depends_on  = [github-ipam_allocation.subnet]
}

# Wiring into AWS (commented out so the example runs with only a GitHub
# token):
#
# resource "aws_vpc" "this" {
#   cidr_block = github-ipam_allocation.vpc.cidr
# }
#
# resource "aws_subnet" "this" {
#   for_each          = github-ipam_allocation.subnet
#   vpc_id            = aws_vpc.this.id
#   cidr_block        = each.value.cidr
#   availability_zone = local.subnets[each.key].az
#   tags              = { Name = each.value.name, Tier = local.subnets[each.key].tier }
# }
