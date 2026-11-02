output "vpc_id" {
  description = "VPC id."
  value       = module.network.vpc_id
}

output "azs" {
  description = "Availability zones in use."
  value       = module.network.azs
}

output "public_subnet_ids" {
  description = "Public subnets (ALB, NAT gateways)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private app subnets (ECS tasks)."
  value       = module.network.private_subnet_ids
}

output "isolated_subnet_ids" {
  description = "Isolated database subnets (RDS)."
  value       = module.network.isolated_subnet_ids
}

output "nat_public_ips" {
  description = "NAT gateway public IPs (outbound source addresses)."
  value       = module.network.nat_public_ips
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs."
  value       = module.network.flow_log_group_name
}

output "plan_role_arn" {
  description = "Read-only role for PR plans in this environment (GitHub variable AWS_PLAN_ROLE_ARN)."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role for apply and destroy in this environment (GitHub variable AWS_APPLY_ROLE_ARN)."
  value       = aws_iam_role.apply.arn
}
