# Dev: 2 AZs, one shared NAT gateway, short log retention -> lowest cost.
region      = "us-east-1"
name        = "acme"
environment = "dev"
owner       = "platform-team"
cost_center = "CC-1001"

vpc_cidr         = "10.10.0.0/16"
az_count         = 2
nat_gateway_mode = "single"

interface_endpoints      = ["ecr.api", "ecr.dkr"]
flow_logs_retention_days = 30
