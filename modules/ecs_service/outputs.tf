output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "alb_dns_name" {
  description = "DNS name of the ALB (the service answers here over HTTP)."
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_security_group_id" {
  description = "Security group of the ALB."
  value       = aws_security_group.alb.id
}

output "service_security_group_id" {
  description = "Security group of the service tasks (the only source allowed into the database)."
  value       = aws_security_group.service.id
}

output "task_role_arn" {
  description = "Task role: attach app permissions here."
  value       = aws_iam_role.task.arn
}

output "execution_role_arn" {
  description = "Task execution role."
  value       = aws_iam_role.execution.arn
}

output "log_group_name" {
  description = "CloudWatch log group of the service."
  value       = aws_cloudwatch_log_group.service.name
}
