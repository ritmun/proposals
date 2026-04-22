# Regional Cluster configuration for dev environment
regional_id          = "dev-us-east-1-rc"
environment          = "dev"
app_code             = "rosa-platform"
service_phase        = "development"
cost_center          = "eng-platforms"

# Network configuration
node_instance_types  = ["t3.xlarge"]

# Database configuration
maestro_db_instance_class      = "db.t3.medium"
maestro_db_multi_az            = false
maestro_db_deletion_protection = false

hyperfleet_db_instance_class      = "db.t3.medium"
hyperfleet_db_multi_az            = false
hyperfleet_db_deletion_protection = false

# Message queue configuration
hyperfleet_mq_instance_type = "mq.t3.micro"
hyperfleet_mq_deployment_mode = "SINGLE_INSTANCE"

# Authorization
authz_billing_mode         = "PAY_PER_REQUEST"
authz_enable_pitr          = false
authz_deletion_protection  = false

# Optional features
enable_bastion = true

# DNS
environment_domain = "dev.rosa.platform.example.com"