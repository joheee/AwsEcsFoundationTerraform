locals {
  port = 5432
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids

  tags = { Name = var.name }
}

# No egress rules at all: the database never initiates connections.
resource "aws_security_group" "this" {
  name        = "${var.name}-db"
  description = "PostgreSQL: reachable only from the listed security groups."
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-db" }

  lifecycle {
    create_before_destroy = true
  }
}

# count, not for_each: the ids are unknown until apply, but their number is not.
resource "aws_vpc_security_group_ingress_rule" "from_clients" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from an allowed client security group"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.master_username
  port     = local.port

  # RDS generates the password and keeps it in Secrets Manager, so it is never
  # in the code, the tfvars or the Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = var.backup_retention_days
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"

  iam_database_authentication_enabled = true
  performance_insights_enabled        = true
}
