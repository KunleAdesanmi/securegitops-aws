variable "name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "cidr" {
  type        = string
  description = "VPC CIDR block, e.g. 10.0.0.0/16."
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to spread subnets across."
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnet CIDRs, one per AZ. EKS nodes live here."
}

variable "public_subnets" {
  type        = list(string)
  description = "Public subnet CIDRs for NAT gateways and load balancers."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
