output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "azs" {
  description = "Availability zones in use."
  value       = module.vpc.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_mode" {
  description = "Effective NAT gateway mode."
  value       = module.vpc.nat_gateway_mode
}

output "nat_public_ips" {
  description = "NAT gateway public IPs."
  value       = module.vpc.nat_public_ips
}

output "interface_endpoint_ids" {
  description = "Interface endpoint IDs by service."
  value       = module.vpc.interface_endpoint_ids
}
