locals {
  name = "securegitops-dev"
  azs  = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  tags = {
    Region = "eu-west-2"
    Tier   = "primary"
  }
}

module "vpc" {
  source          = "../../modules/vpc"
  name            = local.name
  cidr            = "10.10.0.0/16"
  azs             = local.azs
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  public_subnets  = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
  tags            = local.tags
}

module "eks" {
  source              = "../../modules/eks"
  name                = local.name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  node_instance_types = ["t3.medium"]
  node_desired_size   = 2
  node_max_size       = 3
  node_min_size       = 1
  tags                = local.tags
}

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "oidc_provider_url" { value = module.eks.oidc_provider_url }
