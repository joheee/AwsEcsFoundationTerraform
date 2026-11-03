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
  description = "Read-only role for PR plans in this environment (repo variable AWS_PLAN_ROLE_ARN_<ENV>, e.g. AWS_PLAN_ROLE_ARN_STAGING)."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role for apply and destroy in this environment (variable AWS_APPLY_ROLE_ARN on the matching GitHub Environment)."
  value       = aws_iam_role.apply.arn
}

output "alb_dns_name" {
  description = "ALB DNS name: the sample service answers here over HTTP."
  value       = module.ecs_service.alb_dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs_service.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.ecs_service.service_name
}

output "service_log_group_name" {
  description = "CloudWatch log group of the service."
  value       = module.ecs_service.log_group_name
}

output "db_address" {
  description = "Database host name (private; reachable only from the service)."
  value       = module.rds_postgres.address
}

output "db_master_secret_arn" {
  description = "Secrets Manager secret with the generated database credentials."
  value       = module.rds_postgres.master_user_secret_arn
}
