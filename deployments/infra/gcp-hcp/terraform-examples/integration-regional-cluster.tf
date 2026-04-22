# GCP HCP Regional Cluster - Integration Environment
# This example shows how to deploy a regional GKE cluster for integration/dev

# Infrastructure ID - unique identifier for this deployment
# Generated via: ./scripts/infra.py new region integration main us-central1
locals {
  infra_id = "nkcw"  # Replace with generated ID

  # Load metadata from YAML files
  infra_registry = yamldecode(file("${path.module}/../../metadata/infra_ids.yaml")).infra_ids
  environments   = yamldecode(file("${path.module}/../../metadata/environments.yaml")).environments

  # Lookup this deployment's metadata
  infra_metadata = local.infra_registry[local.infra_id]
  env_config     = local.environments[local.infra_metadata.environment]

  # Derived values - single source of truth
  environment      = local.infra_metadata.environment  # "integration"
  sector           = local.infra_metadata.sector       # "main"
  region           = local.infra_metadata.region       # "us-central1"
  parent_folder_id = local.env_config.parent_folder_id
}

terraform {
  backend "gcs" {
    bucket = "gcp-hcp-int-global-terraform-state"
    prefix = "region/main/us-central1"
  }
}

# Global infrastructure remote state
data "terraform_remote_state" "global" {
  backend = "gcs"
  config = {
    bucket = local.env_config.state_bucket
    prefix = "global"
  }
}

# Region cluster module
module "region" {
  source = "path/to/terraform/modules/region"

  # Core parameters - all from YAML metadata
  infra_id          = local.infra_id
  environment       = local.environment
  sector            = local.sector
  region            = local.region
  parent_folder_id  = local.parent_folder_id
  global_project_id = data.terraform_remote_state.global.outputs.global.project_id

  # Hosted Cluster DNS Configuration
  # For delegating DNS to customer hosted clusters
  hc_parent_zone_domain = data.terraform_remote_state.global.outputs.global.hc_env_dns_zone_domain
  hc_parent_project_id  = data.terraform_remote_state.global.outputs.global.project_id
  hc_parent_zone_name   = data.terraform_remote_state.global.outputs.global.hc_env_dns_zone_name

  # Integration Environment Configuration
  ##############################################################

  # Disable deletion protection for easier teardown
  deletion_protection = false

  # Allow external traffic for development
  dns_allow_external_traffic = true

  # GKE Cluster Configuration
  cluster_type = "autopilot"  # or "standard" for more control

  # Node configuration (for standard clusters)
  # node_pools = {
  #   default = {
  #     machine_type = "n2-standard-4"
  #     min_count    = 1
  #     max_count    = 10
  #     disk_size_gb = 100
  #   }
  # }

  # Network configuration
  vpc_cidr_range          = "10.0.0.0/16"
  pods_cidr_range         = "10.1.0.0/16"
  services_cidr_range     = "10.2.0.0/16"
  master_ipv4_cidr_block  = "172.16.0.32/28"
  enable_private_endpoint = false  # Allow external access in integration

  # Team IAM Permissions
  # Module defaults already include: viewer, container.clusterViewer, logging.viewer
  # Add additional permissions here
  additional_folder_iam_bindings = {
    team_container_admin = {
      principals = ["group:gcp-hcp-eng@example.com"]
      roles = [
        { role = "roles/container.admin" },
      ]
    }
    team_compute_admin = {
      principals = ["group:gcp-hcp-eng@example.com"]
      roles = [
        { role = "roles/compute.admin" },  # For managing VPCs, firewall rules
      ]
    }
  }

  # Cloud Workflows for Zero Operator Access
  # Allows operations without direct kubectl access
  enable_workflows = true

  # Privileged Access Management (PAM)
  # Grant temporary elevated access for 4 hours
  pam_max_request_duration = "14400s"  # 4 hours for dev work sessions

  # Diagnostician Agent (optional - for build/deploy)
  enable_agent = true
}

# Export all region outputs
output "region" {
  description = "All region module outputs"
  value       = module.region
  sensitive   = true
}

output "cluster_access" {
  description = "Commands to access the cluster"
  value = <<-EOT

  To access the regional cluster:

  1. Get credentials:
     gcloud container clusters get-credentials $(terraform output -json | jq -r '.region.value.cluster_name') \
       --region=${local.region} \
       --project=$(terraform output -json | jq -r '.region.value.project_id')

  2. Verify cluster is running:
     kubectl get nodes
     kubectl get pods -n argocd

  3. Check Fleet Config Sync status:
     gcloud beta container fleet config-management status \
       --project=$(terraform output -json | jq -r '.region.value.project_id')

  4. Watch ArgoCD bootstrap:
     kubectl get applications -n argocd -w

  Bootstrap Process (Autonomous):
  1. GKE cluster registered in Fleet
  2. Fleet Config Sync pulls bootstrap manifests from Git
  3. ArgoCD + External Secrets Operator deployed automatically
  4. ArgoCD root application manages all other apps

  EOT
}

output "next_deployment" {
  description = "Next step: Deploy management clusters"
  value = <<-EOT

  After regional cluster is healthy, deploy management clusters:

  ./scripts/infra.py new management-cluster integration main us-central1
  cd terraform/config/management-cluster/integration/main/us-central1-<INFRA_ID>
  terraform init && terraform apply

  EOT
}
