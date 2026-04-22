# GCP HCP Global Infrastructure - Production Environment
# This example shows how to deploy the global control plane for production environment

terraform {
  # GCS backend for Terraform state
  backend "gcs" {
    bucket = "gcp-hcp-prd-global-terraform-state"
    prefix = "global"
  }
}

module "global" {
  source = "path/to/terraform/modules/global"

  # Core Configuration
  environment = "production"
  sector      = "main"
  region      = "us-central1"

  # GCP Organization Structure
  # folder "GCP HCP Production"
  parent_folder_id = "2147483647"  # Replace with your production folder ID

  # Production-specific settings
  ##############################################################

  # Restrict access - no public endpoints
  dns_allow_external_traffic = false

  # Multi-region replication for high availability
  gcs_location = "us"  # Multi-region bucket

  # Enable deletion protection
  deletion_protection = true

  # Minimal team permissions - use break-glass for changes
  project_iam_bindings = {
    sre_logging_viewer = {
      principals = ["group:gcp-hcp-sre@example.com"]
      roles = [
        { role = "roles/logging.viewer" },
        { role = "roles/logging.privateLogViewer" },
      ]
    }
    sre_monitoring = {
      principals = ["group:gcp-hcp-sre@example.com"]
      roles = [
        { role = "roles/monitoring.viewer" },
      ]
    }
    # Secret admin - restricted to security team only
    security_secret_admin = {
      principals = ["group:gcp-hcp-security@example.com"]
      roles = [
        { role = "roles/secretmanager.admin" },
      ]
    }
  }

  # ArgoCD Root Application Configuration
  argocd_root_app = {
    git_repo     = "https://github.com/your-org/gcp-hcp-infra.git"
    git_revision = "production"  # Use production branch
    git_path     = ""
    auto_sync    = true
    self_heal    = true   # Auto-remediate drift
    prune        = false  # Safety: manual cleanup required
  }

  # GKE Cluster Configuration
  gke_cluster_config = {
    # Autopilot for production workloads
    cluster_type = "autopilot"

    # Private cluster - no public endpoint
    enable_private_endpoint = true
    enable_dns_endpoint     = true  # Use DNS for private access
    master_ipv4_cidr_block  = "172.16.0.0/28"

    # Maintenance window (weekends only, off-peak hours)
    maintenance_window = {
      start_time = "2025-01-04T06:00:00Z"  # Saturday 6 AM UTC
      end_time   = "2025-01-04T10:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }

    # Binary Authorization (require signed images)
    enable_binary_authorization = true

    # Enhanced monitoring
    enable_managed_prometheus = true
  }

  # Cross-project metrics scoping
  # Automatically discovers and monitors all region and management cluster projects
  # Production includes all production-like sectors (main, canary)
  # Excludes: e2e (testing), dev (development)
  monitored_project_ids = local.monitored_projects  # Defined in locals block

  # Retention and compliance
  gcs_retention_days = 90  # 90-day retention for Terraform state
  enable_audit_logs  = true

  # Disaster Recovery
  backup_retention_days = 30
  enable_backup         = true
}

# Local variables for dynamic project discovery
locals {
  environment = "production"

  # Load metadata files (adjust paths as needed)
  infra_registry  = yamldecode(file("${path.module}/../../metadata/infra_ids.yaml")).infra_ids
  region_mappings = yamldecode(file("${path.module}/../../metadata/regions.yaml")).regions

  # Environment abbreviation
  env_abbrev = {
    production = "prd"
  }

  # Type codes
  type_codes = {
    region             = "reg"
    management-cluster = "mgt"
  }

  # Filter for production sectors (exclude e2e, dev)
  filtered_infra_ids = {
    for infra_id, metadata in local.infra_registry :
    infra_id => metadata
    if metadata.environment == local.environment && !contains(["e2e", "dev"], metadata.sector)
  }

  # Construct project IDs for monitoring
  monitored_projects = [
    for infra_id, metadata in local.filtered_infra_ids :
    "${local.env_abbrev[metadata.environment]}-${local.type_codes[metadata.type]}-${local.region_mappings[metadata.region]}-${infra_id}"
  ]
}

# Outputs
output "global" {
  description = "All global module outputs"
  value       = module.global
  sensitive   = true
}

output "monitored_projects" {
  description = "Dynamically discovered production projects being monitored"
  value       = local.monitored_projects
}

output "production_checklist" {
  description = "Production deployment verification checklist"
  value = <<-EOT

  Production Deployment Checklist:

  ✓ Verify deletion_protection = true
  ✓ Verify private cluster endpoint (enable_private_endpoint = true)
  ✓ Verify ArgoCD is using 'production' branch
  ✓ Verify backup is enabled
  ✓ Verify audit logs are enabled
  ✓ Verify maintenance window is during off-peak hours
  ✓ Create GitHub credentials in Secret Manager (manual step)
  ✓ Verify all monitored_projects are correct
  ✓ Run security scan before deployment
  ✓ Coordinate with SRE team for deployment window
  ✓ Test rollback procedure in staging first

  Manual Steps Required:

  1. Create GitHub credentials:
     # DO NOT store credentials in Terraform!
     gcloud secrets create argocd-repo-creds --project=<PROJECT_ID> ...

  2. Verify security posture:
     gcloud scc findings list --organization=<ORG_ID> --filter="category=WORKLOAD_IDENTITY_MISCONFIGURATION"

  3. Enable Binary Authorization:
     gcloud container binauthz policy import <POLICY_FILE> --project=<PROJECT_ID>

  EOT
}
