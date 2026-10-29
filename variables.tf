###############################################################################
# Naming & environment
###############################################################################

variable "name" {
  description = "Short name of the workload / network (e.g. \"payments\"). Used as a prefix for every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,31}$", var.name))
    error_message = "name must be 2-32 characters, start with a letter and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Drives sensible defaults (e.g. NAT gateway mode). One of: dev, stage, prod."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}

###############################################################################
# Addressing & availability zones
###############################################################################

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC. Must be between /16 and /24."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0)) && try(
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24,
      false
    )
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix length between /16 and /24."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across (ignored when `azs` is set). Minimum 2 for high availability."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6 && floor(var.az_count) == var.az_count
    error_message = "az_count must be a whole number between 2 and 6."
  }
}

variable "azs" {
  description = "Explicit list of availability zone names to use (e.g. [\"eu-west-1a\", \"eu-west-1b\"]). When empty, the first `az_count` AZs of the region are selected automatically."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.azs) == 0 || (length(var.azs) >= 2 && length(var.azs) == length(distinct(var.azs)))
    error_message = "azs must be empty or contain at least 2 distinct availability zones."
  }
}

variable "subnet_newbits" {
  description = "Bits added to the VPC prefix to size each automatically computed subnet (4 on a /16 gives /20 subnets). The lower half of the resulting range is used for public subnets, the upper half for private subnets."
  type        = number
  default     = 4

  validation {
    condition     = var.subnet_newbits >= 3 && var.subnet_newbits <= 8 && floor(var.subnet_newbits) == var.subnet_newbits
    error_message = "subnet_newbits must be a whole number between 3 and 8."
  }
}

variable "public_subnet_cidrs" {
  description = "Optional explicit CIDRs for public subnets, one per AZ in AZ order. Leave empty to compute them from `vpc_cidr`."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in public_subnet_cidrs must be a valid IPv4 CIDR."
  }
}

variable "private_subnet_cidrs" {
  description = "Optional explicit CIDRs for private subnets, one per AZ in AZ order. Leave empty to compute them from `vpc_cidr`."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in private_subnet_cidrs must be a valid IPv4 CIDR."
  }
}

variable "map_public_ip_on_launch" {
  description = "Auto-assign public IPv4 addresses to instances launched in public subnets. Disabled by default (security best practice; also note AWS charges for public IPv4)."
  type        = bool
  default     = false
}

variable "public_subnet_tags" {
  description = "Extra tags for public subnets (e.g. { \"kubernetes.io/role/elb\" = \"1\" })."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags for private subnets (e.g. { \"kubernetes.io/role/internal-elb\" = \"1\" })."
  type        = map(string)
  default     = {}
}

###############################################################################
# NAT
###############################################################################

variable "nat_gateway_mode" {
  description = <<-EOT
    How outbound internet access is provided to private subnets:
      - "per_az" : one NAT gateway per AZ (highly available, highest cost) - default for prod
      - "single" : one shared NAT gateway (cheaper, AZ-level single point of failure) - default for dev/stage
      - "none"   : no NAT gateway (fully private subnets; rely on VPC endpoints)
    Leave null to pick the default based on `environment`.
  EOT

  type    = string
  default = null

  validation {
    condition     = var.nat_gateway_mode == null || contains(["per_az", "single", "none"], coalesce(var.nat_gateway_mode, "per_az"))
    error_message = "nat_gateway_mode must be null or one of: per_az, single, none."
  }
}

###############################################################################
# VPC endpoints
###############################################################################

variable "enable_s3_gateway_endpoint" {
  description = "Create an S3 gateway endpoint attached to all route tables (free; required for ECR image layer pulls from private subnets)."
  type        = bool
  default     = true
}

variable "s3_endpoint_policy" {
  description = "Optional JSON IAM policy for the S3 gateway endpoint. Null keeps the AWS default (full access)."
  type        = string
  default     = null
}

variable "interface_endpoints" {
  description = "AWS service short names to expose through interface endpoints in the private subnets (e.g. \"ecr.api\", \"ecr.dkr\", \"logs\", \"sts\")."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr"]

  validation {
    condition     = alltrue([for s in var.interface_endpoints : can(regex("^[a-z0-9][a-z0-9.-]*$", s))])
    error_message = "interface_endpoints entries must be AWS service short names such as \"ecr.api\" or \"logs\"."
  }
}

variable "interface_endpoint_policy" {
  description = "Optional JSON IAM policy applied to every interface endpoint. Null keeps the AWS default (full access)."
  type        = string
  default     = null
}

###############################################################################
# Security & logging
###############################################################################

variable "manage_default_security_group" {
  description = "Take ownership of the VPC default security group and strip all its rules (CIS AWS Foundations 5.4)."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs delivered to a dedicated CloudWatch Logs group."
  type        = bool
  default     = true
}

variable "flow_logs_traffic_type" {
  description = "Traffic captured by flow logs: ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "flow_logs_retention_days" {
  description = "CloudWatch retention for flow logs, in days. Must be a value supported by CloudWatch Logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a retention period supported by CloudWatch Logs (e.g. 30, 90, 365)."
  }
}

variable "flow_logs_kms_key_arn" {
  description = "Optional KMS key ARN used to encrypt the flow logs log group. The key policy must allow the CloudWatch Logs service principal."
  type        = string
  default     = null
}
