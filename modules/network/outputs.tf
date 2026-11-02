output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones in use."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnets (ALB, NAT gateways), one per AZ."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private app subnets (ECS tasks), one per AZ."
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "Isolated database subnets (RDS), one per AZ, no internet route."
  value       = aws_subnet.isolated[*].id
}

output "internet_gateway_id" {
  description = "Internet gateway id."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "NAT gateway ids (one, or one per AZ)."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "NAT gateway public IPs: the addresses outbound traffic comes from."
  value       = aws_eip.nat[*].public_ip
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
