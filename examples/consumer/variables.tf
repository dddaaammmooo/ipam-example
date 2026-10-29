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

variable "name" {
  description = "Name prefix for this network, used in allocation names."
  type        = string
  default     = "payments-dev"
}

variable "pool_id" {
  description = "Pool in config/pools.yaml to allocate the VPC from."
  type        = string
  default     = "development"
}

variable "azs" {
  description = "Availability zones to create subnets in."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}
