# DR region: same modules, smaller footprint to keep cost down.
# In a real failover, you'd scale this up via a runbook or pilot-light pattern.
locals {
  name = "securegitops-dr"
  azs  = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  tags = {
    Region = "eu-west-1"
    Tier   = "dr"
  }
}

module "vpc" {
  source          = "../../modules/vpc"
  name            = local.name
  cidr            = "10.20.0.0/16"
  azs             = local.azs
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]
  tags            = local.tags
}

module "eks" {
  source              = "../../modules/eks"
  name                = local.name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  node_instance_types = ["t3.medium"]
  node_desired_size   = 1
  node_max_size       = 3
  node_min_size       = 1
  tags                = local.tags
}
