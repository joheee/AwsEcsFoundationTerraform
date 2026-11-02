variable "name" {
  description = "Name prefix, e.g. ecs-foundation-staging."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC (a /16 is expected; subnets are /20)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 18
    error_message = "vpc_cidr must be a valid CIDR no smaller than /18."
  }
}

variable "az_count" {
  description = "Number of availability zones to span (2 or 3)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "nat_gateway_per_az" {
  description = "true: one NAT gateway per AZ (resilient, prod). false: a single shared NAT gateway (cheaper, staging)."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention of the VPC flow log group in CloudWatch Logs."
  type        = number
  default     = 14
}
