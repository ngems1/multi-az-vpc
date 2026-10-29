provider "aws" {
  region = var.region

  # Organisation-wide tags applied by the provider to every resource.
  default_tags {
    tags = {
      Project    = var.name
      Owner      = var.owner
      CostCenter = var.cost_center
      Repository = "terraform-aws-multi-az-vpc"
    }
  }
}

module "vpc" {
  source = "../../"

  name        = var.name
  environment = var.environment

  vpc_cidr         = var.vpc_cidr
  az_count         = var.az_count
  nat_gateway_mode = var.nat_gateway_mode

  enable_s3_gateway_endpoint = true
  interface_endpoints        = var.interface_endpoints

  flow_logs_retention_days = var.flow_logs_retention_days

  # Tags that let EKS / AWS Load Balancer Controller discover the subnets.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}
