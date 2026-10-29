# Stage: mirrors prod topology (3 AZs) but shares one NAT gateway to save cost.
region      = "us-east-1"
name        = "acme"
environment = "stage"
owner       = "platform-team"
cost_center = "CC-1001"

vpc_cidr         = "10.20.0.0/16"
az_count         = 3
nat_gateway_mode = "single"

interface_endpoints      = ["ecr.api", "ecr.dkr", "logs"]
flow_logs_retention_days = 90
