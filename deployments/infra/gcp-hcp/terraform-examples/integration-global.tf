# GCP HCP Global Infrastructure - Integration Environment
# This example shows how to deploy the global control plane for integration/dev environment

terraform {
  # GCS backend for Terraform state
  backend "gcs" {
    bucket = "gcp-hcp-int-global-terraform-state"
    prefix = "global"
  }
}

module "global" {
  source = "path/to/terraform/modules/global"

  # Core Configuration
  environment = "integration"
  sector      = "main"
  region      = "us-central1"

  # GCP Organization Structure
  # folder "GCP HCP Integration" (example ID)
  parent_folder_id = "1059025110045"

  # Integration-specific settings
  ##############################################################

  # Allow direct access from developer laptops (integration only)
  dns_allow_external_traffic = true

  # Limit to single region for cost control
  gcs_location = "us-central1"

  # Disable deletion protection for easier teardown
  deletion_protection = false

  # Team IAM Permissions on Global Project
  project_iam_bindings = {
    team_secret_admin = {
      principals = ["group:gcp-hcp-eng@example.com"]
      roles = [
        { role = "roles/secretmanager.admin" },
      ]
    }
    team_logging = {
      principals = ["group:gcp-hcp-eng@example.com"]
      roles = [
        { role = "roles/logging.viewer" },
        { role = "roles/logging.privateLogViewer" },
      ]
    }
    team_container_developer = {
      principals = ["group:gcp-hcp-eng@example.com"]
      roles = [
        { role = "roles/container.developer" },
      ]
    }
  }

  # ArgoCD Root Application Configuration
  argocd_root_app = {
    git_repo     = "https://github.com/your-org/gcp-hcp-infra.git"
    git_revision = "main"
    git_path     = ""  # defaults to argocd/rendered/global/{environment}/{sector}/{region}
    auto_sync    = true
    self_heal    = true
    prune        = false  # Safety: prevent accidental deletions
  }

  # GKE Cluster Configuration
  gke_cluster_config = {
    # Autopilot for fully managed nodes
    cluster_type = "autopilot"

    # Network configuration
    enable_private_endpoint = false  # Allow external access for dev
    enable_dns_endpoint     = false
    master_ipv4_cidr_block  = "172.16.0.0/28"

    # Maintenance window (PST timezone, weekdays only)
    maintenance_window = {
      start_time = "2025-01-01T09:00:00Z"
      end_time   = "2025-01-01T17:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    }
  }

  # Cloud Build Integration (optional - for CI/CD)
  enable_agent                   = true
  agent_cloudbuild_connection_id = "projects/gcp-hcp-int-global/locations/us-central1/connections/gcp-hcp-infra"
}

# Outputs
output "global" {
  description = "All global module outputs"
  value       = module.global
  sensitive   = true  # Contains cluster endpoint and credentials
}

output "next_steps" {
  description = "Post-deployment manual steps"
  value = <<-EOT

  Next steps after 'terraform apply':

  1. Create GitHub credentials for ArgoCD:

     PROJECT_ID=$(terraform output -json | jq -r '.global.value.project_id')

     echo '{
       "url": "https://github.com/your-org/gcp-hcp-infra.git",
       "username": "your-github-username",
       "password": "github_pat_..."
     }' | gcloud secrets create argocd-repo-creds \
       --project=$PROJECT_ID \
       --data-file=- \
       --replication-policy=automatic

  2. Migrate Terraform state to GCS:

     BUCKET=$(terraform output -json | jq -r '.global.value.terraform_state_bucket')
     # Add backend "gcs" block to main.tf (shown above)
     terraform init -migrate-state

  3. Access the GKE cluster:

     $(terraform output -json | jq -r '.global.value.gcloud_get_credentials_command')
     kubectl get pods -n argocd

  EOT
}
