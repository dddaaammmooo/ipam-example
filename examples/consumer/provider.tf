# Points the provider at this IPAM repository. Every consumer stack (VPCs,
# EKS clusters, VPNs) uses the same block; only the token differs.
#
# The token must be passed in explicitly: despite the provider docs, v0.0.21
# does not fall back to the GITHUB_TOKEN environment variable. Export
# TF_VAR_github_token instead.
provider "github-ipam" {
  token      = var.github_token
  owner      = var.ipam_owner
  repository = var.ipam_repository
  branch     = "main"

  # Defaults, shown for clarity.
  pools_file       = "config/pools.yaml"
  allocations_file = "config/allocations.yaml"

  # Optimistic concurrency: on a SHA conflict (another apply wrote first)
  # the provider re-reads allocations.yaml and retries with backoff.
  max_retries   = 10
  base_delay_ms = 200
}
