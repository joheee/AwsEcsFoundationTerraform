output "address" {
  description = "Database host name."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Database port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Master user name."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the generated master credentials (JSON with username and password)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "Database security group."
  value       = aws_security_group.this.id
}
