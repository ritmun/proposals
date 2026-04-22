# Regional Cluster configuration for production environment
regional_id          = "prod-us-east-1-rc"
environment          = "prod"
app_code             = "rosa-platform"
service_phase        = "production"
cost_center          = "eng-platforms"

# Network configuration
node_instance_types  = ["m5.2xlarge", "m5.4xlarge"]

# Database configuration
maestro_db_instance_class      = "db.r5.xlarge"
maestro_db_multi_az            = true
maestro_db_deletion_protection = true
maestro_db_backup_retention    = 30

hyperfleet_db_instance_class      = "db.r5.xlarge"
hyperfleet_db_multi_az            = true
hyperfleet_db_deletion_protection = true
hyperfleet_db_backup_retention    = 30

# Message queue configuration
hyperfleet_mq_instance_type = "mq.m5.large"
hyperfleet_mq_deployment_mode = "ACTIVE_STANDBY_MULTI_AZ"

# Authorization
authz_billing_mode         = "PROVISIONED"
authz_read_capacity        = 100
authz_write_capacity       = 100
authz_enable_pitr          = true
authz_deletion_protection  = true

# Optional features
enable_bastion = false

# DNS
environment_domain = "rosa.platform.example.com"

# High availability
enable_multi_az = true
min_size        = 3
max_size        = 10
desired_size    = 5