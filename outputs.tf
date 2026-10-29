output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones used, in order."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs, ordered like `azs`."
  value       = [for az in local.azs : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs, ordered like `azs`."
  value       = [for az in local.azs : aws_subnet.private[az].id]
}

output "public_subnets_by_az" {
  description = "Map of AZ => { id, cidr_block } for public subnets."
  value       = { for az, s in aws_subnet.public : az => { id = s.id, cidr_block = s.cidr_block } }
}

output "private_subnets_by_az" {
  description = "Map of AZ => { id, cidr_block } for private subnets."
  value       = { for az, s in aws_subnet.private : az => { id = s.id, cidr_block = s.cidr_block } }
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  description = "ID of the shared public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Private route table IDs, ordered like `azs`."
  value       = [for az in local.azs : aws_route_table.private[az].id]
}

output "nat_gateway_mode" {
  description = "Effective NAT gateway mode (per_az, single or none)."
  value       = local.nat_gateway_mode
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs (empty when nat_gateway_mode = none)."
  value       = [for az in local.nat_azs : aws_nat_gateway.this[az].id]
}

output "nat_public_ips" {
  description = "Public Elastic IPs of the NAT gateways (useful for partner allow-lists)."
  value       = [for az in local.nat_azs : aws_eip.nat[az].public_ip]
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint, or null when disabled."
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "interface_endpoint_ids" {
  description = "Map of service short name => interface endpoint ID."
  value       = { for svc, ep in aws_vpc_endpoint.interface : svc => ep.id }
}

output "endpoints_security_group_id" {
  description = "Security group attached to interface endpoints, or null when none are created."
  value       = try(aws_security_group.endpoints[0].id, null)
}

output "flow_log_id" {
  description = "ID of the VPC flow log, or null when disabled."
  value       = try(aws_flow_log.this[0].id, null)
}

output "flow_log_group_name" {
  description = "CloudWatch Logs group receiving flow logs, or null when disabled."
  value       = try(aws_cloudwatch_log_group.flow_logs[0].name, null)
}
