variable "aws_region" {
  description = "Region for everything in this repo (the org SCP blocks the rest)."
  type        = string
  default     = "ap-southeast-2"
}

variable "project" {
  description = "Project name, used as tag value and resource name prefix."
  type        = string
  default     = "ecs-foundation"
}

variable "environment" {
  description = "Environment name: staging or prod. Adding a third is a new tfvars and backend file."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.environment))
    error_message = "environment must be lowercase letters, digits and dashes, 2-15 characters."
  }
}

variable "state_bucket_name" {
  description = "Name of the hand-made Terraform state bucket (same as in envs/<env>.backend.hcl). Used to scope the CI role policies."
  type        = string
  default     = "joheee-ecs-foundation-tfstate"
}

variable "github_repo" {
  description = "GitHub repo (owner/name) the CI roles trust. The only repo allowed."
  type        = string
  default     = "joheee/AwsEcsFoundationTerraform"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must be exactly owner/name, with no wildcards."
  }
}

variable "github_branch" {
  description = "Branch whose workflow runs may assume the apply role."
  type        = string
  default     = "main"
}

variable "vpc_cidr" {
  description = "CIDR of the VPC. Keep it unique per environment."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones (2 or 3)."
  type        = number
  default     = 2
}

variable "nat_gateway_per_az" {
  description = "One NAT gateway per AZ (prod) or a single shared one (staging)."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention of the VPC flow log group."
  type        = number
  default     = 14
}
