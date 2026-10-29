variable "github_token" {
  description = "Token with Contents read/write on the IPAM repository (fine-grained PAT or GitHub App installation token)."
  type        = string
  sensitive   = true
}

variable "ipam_owner" {
  description = "Owner of the IPAM repository."
  type        = string
  default     = "dddaaammmooo"
}

variable "ipam_repository" {
  description = "Name of the IPAM repository."
  type        = string
  default     = "ipam-example"
}

variable "env_pools" {
  description = "Which pool in config/pools.yaml each environment's VPCs come from."
  type        = map(string)
  default = {
    dev = "development"
    stg = "staging"
    prd = "prod-eu-west-1"
  }
}

variable "azs" {
  description = "Availability zones; every tier gets one subnet per AZ."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "publish_to_ssm" {
  description = "Publish each VPC's CIDRs to SSM Parameter Store in its application account. Off by default so the example runs with only a GitHub token."
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "Region the VPCs (and their SSM parameters) live in."
  type        = string
  default     = "eu-west-1"
}

variable "ssm_publisher_role_name" {
  description = "IAM role assumed in every application account to write the parameters (see README for its policy)."
  type        = string
  default     = "ipam-ssm-publisher"
}

variable "ssm_prefix" {
  description = "Parameter path prefix in each application account."
  type        = string
  default     = "/platform/network"
}
