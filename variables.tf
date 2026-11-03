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

# ---------------------------------------------------------------------------
# Container platform
# ---------------------------------------------------------------------------
variable "container_image" {
  description = "Image the service runs (a public sample image by default)."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "service_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "service_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "service_desired_count" {
  description = "Number of running tasks."
  type        = number
  default     = 1
}

variable "alb_deletion_protection" {
  description = "Deletion protection on the ALB."
  type        = bool
  default     = false
}

variable "container_insights" {
  description = "CloudWatch Container Insights on the ECS cluster (extra cost)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "17"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Initial database storage in GiB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Multi-AZ database (prod)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Deletion protection on the database (prod)."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot when the database is destroyed (staging)."
  type        = bool
  default     = true
}
