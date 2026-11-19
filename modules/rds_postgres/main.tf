locals {
  port = 5432

  # "17" or "17.4" -> postgres17. A major version upgrade needs a new group,
  # which create_before_destroy below handles.
  parameter_group_family = "postgres${split(".", var.engine_version)[0]}"
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

# RDS writes these log groups itself once log exports are on. Creating them
# here gives them a retention period; otherwise they never expire and are left
# behind after a destroy. Names are fixed by RDS: /aws/rds/instance/<id>/<log>.
locals {
  log_exports = ["postgresql", "upgrade"]
}

resource "aws_cloudwatch_log_group" "export" {
  for_each = toset(local.log_exports)

  name              = "/aws/rds/instance/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

# CKV2_AWS_30: query logging. DDL statements and anything slower than one
# second go to the postgresql log, which is exported to CloudWatch below. Both
# parameters are dynamic, so no reboot is needed. "ddl" rather than "all" keeps
# application queries (and any values in them) out of the logs.
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = local.parameter_group_family
  description = "${var.name}: query logging"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_ms)
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CKV_AWS_118: enhanced monitoring (OS metrics every 60 s). RDS needs a role it
# can assume to publish them. The role name must stay "<name>-rds-monitoring":
# the root module's apply policy lists it in service_role_arns.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "monitoring_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    # Confused-deputy guard: only this account's instance with this name.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:rds:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:db:${var.name}"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_trust.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
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

  # Prowler rds_instance_extended_support: do not enrol in paid RDS Extended
  # Support. After the engine's standard support ends, RDS upgrades it instead
  # of charging for extended support, so plan the next major version before then.
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"

  # Without this, RDS accepted the lifecycle change but kept the old value until
  # the maintenance window. Off by default so prod changes wait for its window.
  apply_immediately = var.apply_immediately

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"

  iam_database_authentication_enabled = true
  performance_insights_enabled        = true

  parameter_group_name = aws_db_parameter_group.this.name

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.monitoring.arn

  # CKV_AWS_129: ship the engine and upgrade logs to CloudWatch.
  enabled_cloudwatch_logs_exports = local.log_exports

  # The log groups must exist first, or RDS creates them without retention.
  depends_on = [
    aws_cloudwatch_log_group.export,
    aws_iam_role_policy_attachment.monitoring,
  ]
}
