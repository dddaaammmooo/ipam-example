output "vpc_cidrs" {
  description = "VPC block per product and environment."
  value       = { for k, a in github-ipam_allocation.vpc : k => a.cidr }
}

output "subnet_cidrs" {
  description = "Subnet CIDR per product, environment, tier and AZ."
  value       = { for k, s in github-ipam_allocation.subnet : k => s.cidr }
}

output "aws_vpc_cidr_blocks" {
  description = "VPC blocks split into /16-or-smaller pieces that AWS accepts (first = primary CIDR)."
  value       = local.aws_vpc_cidr_blocks
}
