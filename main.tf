###############################################################################
# Lookups
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"

  # Exclude Local Zones / Wavelength Zones, which need explicit opt-in.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  name_prefix = "${var.name}-${var.environment}"

  # Sorted so the selection is deterministic between runs.
  discovered_azs = sort(data.aws_availability_zones.available.names)

  azs = length(var.azs) > 0 ? var.azs : slice(
    local.discovered_azs, 0, min(var.az_count, length(local.discovered_azs))
  )
  az_index = { for i, az in local.azs : az => i }

  # Automatic layout: subnet slots [0, half) are public, [half, 2*half) private.
  # Indexes are fixed per AZ position, so adding an AZ later never renumbers
  # (and therefore never replaces) existing subnets.
  vpc_prefix     = tonumber(split("/", var.vpc_cidr)[1])
  private_offset = pow(2, var.subnet_newbits) / 2

  public_subnets = {
    for az, i in local.az_index :
    az => try(var.public_subnet_cidrs[i], cidrsubnet(var.vpc_cidr, var.subnet_newbits, i))
  }
  private_subnets = {
    for az, i in local.az_index :
    az => try(var.private_subnet_cidrs[i], cidrsubnet(var.vpc_cidr, var.subnet_newbits, i + local.private_offset))
  }

  nat_gateway_mode = coalesce(var.nat_gateway_mode, var.environment == "prod" ? "per_az" : "single")

  # AZs that host a NAT gateway.
  nat_azs = (
    local.nat_gateway_mode == "per_az" ? local.azs :
    local.nat_gateway_mode == "single" ? [local.azs[0]] :
    []
  )

  # Which NAT gateway (keyed by AZ) each private route table uses.
  nat_for_az = contains(["per_az", "single"], local.nat_gateway_mode) ? {
    for az in local.azs : az => (local.nat_gateway_mode == "per_az" ? az : local.azs[0])
  } : {}

  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "terraform-aws-multi-az-vpc"
    },
    var.tags,
  )
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # required for private DNS on interface endpoints
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })

  lifecycle {
    precondition {
      condition     = length(var.azs) > 0 || length(local.discovered_azs) >= var.az_count
      error_message = "The region does not have enough available AZs for the requested az_count."
    }
    precondition {
      condition     = length(local.azs) <= local.private_offset
      error_message = "Too many AZs for subnet_newbits: increase subnet_newbits so that 2^subnet_newbits >= 2 * number_of_azs."
    }
    precondition {
      condition     = local.vpc_prefix + var.subnet_newbits <= 28
      error_message = "vpc_cidr prefix + subnet_newbits must be <= 28 (AWS minimum subnet size is /28)."
    }
    precondition {
      condition     = length(var.public_subnet_cidrs) == 0 || length(var.public_subnet_cidrs) == length(local.azs)
      error_message = "public_subnet_cidrs must be empty or contain exactly one CIDR per AZ."
    }
    precondition {
      condition     = length(var.private_subnet_cidrs) == 0 || length(var.private_subnet_cidrs) == length(local.azs)
      error_message = "private_subnet_cidrs must be empty or contain exactly one CIDR per AZ."
    }
  }
}

# Strip every rule from the default security group so nothing can accidentally
# rely on it (CIS AWS Foundations Benchmark 5.4).
resource "aws_default_security_group" "this" {
  count = var.manage_default_security_group ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-default-sg-do-not-use" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-igw" })
}

###############################################################################
# Subnets
###############################################################################

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-public-${each.key}", Tier = "public" },
    var.public_subnet_tags,
  )
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-private-${each.key}", Tier = "private" },
    var.private_subnet_tags,
  )
}

###############################################################################
# Public routing
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-rt", Tier = "public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# NAT gateways
###############################################################################

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  #checkov:skip=CKV2_AWS_19:EIP is attached to a NAT gateway, not an EC2 instance.
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nat-eip-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Private routing (one route table per AZ so per-AZ NAT is always possible)
###############################################################################

resource "aws_route_table" "private" {
  for_each = toset(local.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-rt-${each.key}", Tier = "private" })
}

resource "aws_route" "private_nat" {
  for_each = local.nat_for_az

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.value].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
