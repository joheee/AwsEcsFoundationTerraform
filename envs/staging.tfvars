# Staging: cheapest sensible sizing. Non-secret values only.
environment = "staging"
vpc_cidr    = "10.10.0.0/16"

nat_gateway_per_az      = false # one shared NAT gateway
flow_log_retention_days = 14

service_desired_count = 1
service_cpu           = 256
service_memory        = 512

db_instance_class        = "db.t4g.micro"
db_allocated_storage     = 20
db_multi_az              = false
db_backup_retention_days = 7
db_deletion_protection   = false
db_skip_final_snapshot   = true
