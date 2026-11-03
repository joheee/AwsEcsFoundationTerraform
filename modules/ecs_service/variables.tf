variable "name" {
  description = "Name prefix, e.g. ecs-foundation-staging."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster, ALB and service live in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB (at least two, in different AZs)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate tasks."
  type        = list(string)
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB on port 80."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alb_deletion_protection" {
  description = "Deletion protection on the ALB (on in prod)."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "Image the service runs. A public sample image by default; app CI/CD is out of scope."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "ALB target group health check path."
  type        = string
  default     = "/"
}

variable "cpu" {
  description = "Fargate task CPU units (256, 512, 1024, ...)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB (must be a valid pair with cpu)."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of running tasks."
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "Plain (non-secret) environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Container secrets as NAME => Secrets Manager valueFrom (arn, or arn:json-key::). Never plain values."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Secrets Manager ARNs the execution role may read (the secrets above). Keeps the policy scoped to exactly these."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Retention of the service log group."
  type        = number
  default     = 14
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights on the cluster (extra cost)."
  type        = bool
  default     = false
}
