###############################################################################
# VPC endpoints
#
# Service names are resolved through `aws_vpc_endpoint_service` instead of being
# hard-coded as "com.amazonaws.<region>.<service>", so the module works in every
# region and partition (commercial, GovCloud, China).
###############################################################################

# --- S3 gateway endpoint (no hourly charge) ----------------------------------

data "aws_vpc_endpoint_service" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  service      = "s3"
  service_type = "Gateway"
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = data.aws_vpc_endpoint_service.s3[0].service_name
  vpc_endpoint_type = "Gateway"
  policy            = var.s3_endpoint_policy

  # Attach to public and every private route table.
  route_table_ids = concat(
    [aws_route_table.public.id],
    [for az in local.azs : aws_route_table.private[az].id],
  )

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-s3" })
}

# --- Interface endpoints (ECR API / ECR DKR by default) ----------------------

data "aws_vpc_endpoint_service" "interface" {
  for_each = toset(var.interface_endpoints)

  service      = each.key
  service_type = "Interface"
}

resource "aws_security_group" "endpoints" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  #checkov:skip=CKV2_AWS_5:Attached to the interface VPC endpoints below.
  name_prefix = "${local.name_prefix}-vpce-"
  description = "Allow HTTPS from inside the VPC to interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  # No egress rules: endpoint ENIs only answer inbound connections.

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from the VPC CIDR"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = aws_vpc.this.cidr_block

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-https-in" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = data.aws_vpc_endpoint_service.interface[each.key].service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  policy              = var.interface_endpoint_policy

  subnet_ids         = [for az in local.azs : aws_subnet.private[az].id]
  security_group_ids = [aws_security_group.endpoints[0].id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-${replace(each.key, ".", "-")}" })
}
