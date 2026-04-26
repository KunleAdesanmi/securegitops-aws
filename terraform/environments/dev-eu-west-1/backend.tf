terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
  backend "s3" {
    bucket         = "securegitops-tfstate-563046585342"
    key            = "dev-eu-west-1/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "securegitops-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-west-1"
  default_tags {
    tags = {
      Project     = "securegitops"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
