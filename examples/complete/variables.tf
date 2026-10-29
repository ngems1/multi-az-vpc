variable "region" {
  description = "AWS region to deploy into (any commercial, GovCloud or China region)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must look like an AWS region code, e.g. us-east-1 or eu-west-3."
  }
}

variable "name" {
  description = "Workload name used as a resource prefix."
  type        = string
}

variable "environment" {
  description = "dev, stage or prod."
  type        = string
}

variable "owner" {
  description = "Team or person accountable for the resources (tag)."
  type        = string
}

variable "cost_center" {
  description = "Cost center used for chargeback (tag)."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones."
  type        = number
  default     = 3
}

variable "nat_gateway_mode" {
  description = "per_az, single, none or null (environment default)."
  type        = string
  default     = null
}

variable "interface_endpoints" {
  description = "Interface endpoints to create."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr"]
}

variable "flow_logs_retention_days" {
  description = "Flow log retention in days."
  type        = number
  default     = 365
}
