# Prod: 3 AZs, one NAT gateway per AZ (default for prod), 1-year log retention.
region      = "eu-west-1"
name        = "acme"
environment = "prod"
owner       = "platform-team"
cost_center = "CC-1001"

vpc_cidr = "10.30.0.0/16"
az_count = 3
# nat_gateway_mode left unset -> "per_az" because environment = "prod"

interface_endpoints      = ["ecr.api", "ecr.dkr", "logs", "sts"]
flow_logs_retention_days = 365
