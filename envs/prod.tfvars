# Prod: same code, resilient settings. Non-secret values only.
environment = "prod"
vpc_cidr    = "10.20.0.0/16"

nat_gateway_per_az      = true # one NAT gateway per AZ
flow_log_retention_days = 90

service_desired_count   = 2
service_cpu             = 512
service_memory          = 1024
alb_deletion_protection = true
container_insights      = true

db_instance_class        = "db.t4g.small"
db_allocated_storage     = 50
db_multi_az              = true
db_backup_retention_days = 14
db_deletion_protection   = true
db_skip_final_snapshot   = false
