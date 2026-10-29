# Unit tests for the module. They use a mocked AWS provider, so they run in
# CI without AWS credentials and without creating real resources.
#
#   terraform init && terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      # Deliberately unsorted: the module must sort them deterministically.
      names    = ["us-east-1c", "us-east-1a", "us-east-1d", "us-east-1b", "us-east-1f", "us-east-1e"]
      zone_ids = ["use1-az1", "use1-az2", "use1-az3", "use1-az4", "use1-az5", "use1-az6"]
    }
  }

  mock_data "aws_vpc_endpoint_service" {
    defaults = {
      service_name = "com.amazonaws.us-east-1.mock"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name        = "acme"
  environment = "dev"
}

###############################################################################
# Happy paths
###############################################################################

run "dev_defaults" {
  command = plan

  assert {
    condition     = output.azs == tolist(["us-east-1a", "us-east-1b", "us-east-1c"])
    error_message = "Expected the first three AZs in sorted order."
  }

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3
    error_message = "Expected one public and one private subnet per AZ."
  }

  assert {
    condition     = aws_subnet.public["us-east-1a"].cidr_block == "10.0.0.0/20" && aws_subnet.public["us-east-1c"].cidr_block == "10.0.32.0/20"
    error_message = "Public subnets should occupy the lower half of the VPC range."
  }

  assert {
    condition     = aws_subnet.private["us-east-1a"].cidr_block == "10.0.128.0/20" && aws_subnet.private["us-east-1c"].cidr_block == "10.0.160.0/20"
    error_message = "Private subnets should occupy the upper half of the VPC range."
  }

  assert {
    condition     = output.nat_gateway_mode == "single" && length(aws_nat_gateway.this) == 1
    error_message = "dev should default to a single NAT gateway."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "Every private route table should have a default route via NAT."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPs by default."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "DNS support and hostnames are required for private DNS on interface endpoints."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1 && aws_vpc_endpoint.s3[0].vpc_endpoint_type == "Gateway"
    error_message = "Expected an S3 gateway endpoint."
  }

  assert {
    condition     = toset(keys(aws_vpc_endpoint.interface)) == toset(["ecr.api", "ecr.dkr"])
    error_message = "Expected ECR API and ECR DKR interface endpoints by default."
  }

  assert {
    condition     = alltrue([for ep in aws_vpc_endpoint.interface : ep.private_dns_enabled && ep.vpc_endpoint_type == "Interface"])
    error_message = "Interface endpoints must have private DNS enabled."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.endpoints_https[0].from_port == 443 && aws_vpc_security_group_ingress_rule.endpoints_https[0].cidr_ipv4 == "10.0.0.0/16"
    error_message = "Endpoint security group should only allow HTTPS from the VPC CIDR."
  }

  assert {
    condition     = length(aws_flow_log.this) == 1 && aws_flow_log.this[0].traffic_type == "ALL"
    error_message = "Flow logs should be enabled by default."
  }

  assert {
    condition     = length(aws_default_security_group.this) == 1
    error_message = "The default security group should be managed (and emptied) by default."
  }

  assert {
    condition     = aws_vpc.this.tags["Name"] == "acme-dev-vpc" && aws_vpc.this.tags["Environment"] == "dev"
    error_message = "Resources should follow the <name>-<environment> naming convention and be tagged."
  }
}

run "prod_defaults_to_nat_per_az" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = output.nat_gateway_mode == "per_az" && length(aws_nat_gateway.this) == 3 && length(aws_eip.nat) == 3
    error_message = "prod should default to one NAT gateway per AZ."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "Each AZ should route through its own NAT gateway."
  }
}

run "nat_none_creates_no_nat_or_routes" {
  command = plan

  variables {
    nat_gateway_mode = "none"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0
    error_message = "nat_gateway_mode = none must not create NAT gateways, EIPs or default routes."
  }
}

run "explicit_azs_and_custom_cidr" {
  command = plan

  variables {
    environment    = "stage"
    azs            = ["us-east-1b", "us-east-1d"]
    vpc_cidr       = "172.20.0.0/16"
    subnet_newbits = 6
  }

  assert {
    condition     = toset(keys(aws_subnet.public)) == toset(["us-east-1b", "us-east-1d"])
    error_message = "Explicit AZs should be used verbatim."
  }

  assert {
    condition     = aws_subnet.public["us-east-1b"].cidr_block == "172.20.0.0/22" && aws_subnet.private["us-east-1b"].cidr_block == "172.20.128.0/22"
    error_message = "Custom CIDR / newbits layout is wrong."
  }
}

run "explicit_subnet_cidrs" {
  command = plan

  variables {
    az_count             = 2
    vpc_cidr             = "10.50.0.0/16"
    public_subnet_cidrs  = ["10.50.0.0/24", "10.50.1.0/24"]
    private_subnet_cidrs = ["10.50.10.0/23", "10.50.12.0/23"]
  }

  assert {
    condition     = aws_subnet.private["us-east-1b"].cidr_block == "10.50.12.0/23"
    error_message = "Explicit subnet CIDRs should be honoured in AZ order."
  }
}

run "optional_features_disabled" {
  command = plan

  variables {
    enable_flow_logs              = false
    enable_s3_gateway_endpoint    = false
    interface_endpoints           = []
    manage_default_security_group = false
  }

  assert {
    condition = (
      length(aws_flow_log.this) == 0 &&
      length(aws_iam_role.flow_logs) == 0 &&
      length(aws_vpc_endpoint.s3) == 0 &&
      length(aws_vpc_endpoint.interface) == 0 &&
      length(aws_security_group.endpoints) == 0 &&
      length(aws_default_security_group.this) == 0
    )
    error_message = "Disabled features must not create any resources."
  }
}

run "apply_with_mocks_produces_outputs" {
  # Full apply against the mock provider: exercises outputs end to end.
  command = apply

  assert {
    condition     = length(output.public_subnet_ids) == 3 && length(output.private_subnet_ids) == 3
    error_message = "Subnet ID outputs should contain one entry per AZ."
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 1 && output.flow_log_id != null
    error_message = "Expected one NAT gateway ID and a flow log ID."
  }
}

###############################################################################
# Input validation & guard rails
###############################################################################

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "rejects_single_az" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}

run "rejects_invalid_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/8"
  }

  expect_failures = [var.vpc_cidr]
}

run "rejects_invalid_nat_mode" {
  command = plan

  variables {
    nat_gateway_mode = "two"
  }

  expect_failures = [var.nat_gateway_mode]
}

run "rejects_mismatched_subnet_cidrs" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.0.0.0/24"]
  }

  expect_failures = [aws_vpc.this]
}
