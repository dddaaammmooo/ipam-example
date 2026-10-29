output "vpc_cidr" {
  value = github-ipam_allocation.vpc.cidr
}

output "growth_reservation_cidr" {
  value = github-ipam_allocation.vpc_growth.cidr
}

output "subnet_cidrs" {
  value = { for k, s in github-ipam_allocation.subnet : k => s.cidr }
}

output "allocations_in_vpc" {
  value = [for a in data.github-ipam_allocations.in_vpc.allocations : "${a.cidr} ${a.name}"]
}
