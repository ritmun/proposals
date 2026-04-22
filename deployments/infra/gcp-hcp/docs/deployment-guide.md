# GCP HCP - Deployment Guide (Proposed)

> **Platform**: Google Cloud Platform Hypershift Control Plane (GCP HCP)
> **Deployment Method**: Terraform with Fleet Config Sync autonomous bootstrap (Proposed)
> **Repository Reference**: [gcp-hcp-infra](https://github.com/openshift-online/gcp-hcp-infra)
> **Status**: Proposed alternative pattern to GitHub Actions approach

This guide provides documentation on the proposed GCP HCP deployment pattern, which uses a unique Fleet Config Sync approach as an alternative to the GitHub Actions pattern proposed for ROSA HCP.

---

## Overview

GCP HCP uses a unique deployment approach that differs from both ARO-HCP and the proposed ROSA HCP pattern, leveraging GCP-native automation and Fleet-based management:

- **Terraform** for infrastructure as code
- **Fleet Config Sync** for autonomous cluster bootstrapping
- **GCS** for Terraform state with built-in locking
- **Workload Identity** for keyless authentication
- **GCP Secret Manager** for native secret management

**📘 Complete Official Guide**: [GCP HCP Deployment Guide](https://github.com/openshift-online/gcp-hcp-infra/blob/main/docs/DEPLOYMENT_GUIDE.md)

---

## Deployment Architecture

Unlike ROSA's GitHub Actions-based approach, GCP HCP uses:

| **Component** | **Purpose** | **GCP HCP Approach** |
|---------------|-------------|---------------------|
| **IaC Execution** | Running Terraform | Manual `terraform apply` or Cloud Build (optional) |
| **State Management** | Terraform state storage | GCS bucket with built-in locking |
| **Authentication** | GCP access | `gcloud auth` + Application Default Credentials |
| **Cluster Bootstrap** | Autonomous cluster setup | **Fleet Config Sync** (unique to GCP) |
| **GitOps** | Application deployment | ArgoCD (auto-bootstrapped by Fleet) |
| **Secret Management** | Runtime secrets | External Secrets + GCP Secret Manager |

---

## Key Deployment Stages

### 1. Global Infrastructure

Deploy environment-level control plane (one per environment: dev/integration/stage/prod):

```bash
cd terraform/config/global/integration/main/us-central1

# Initialize and apply
terraform init
terraform apply

# Migrate state to GCS after first apply
BUCKET=$(terraform output -json | jq -r '.global.value.terraform_state_bucket')
# Add backend "gcs" block to main.tf, then:
terraform init -migrate-state
```

**Creates**:
- GCP project with enabled APIs
- GKE Autopilot cluster (private)
- ArgoCD with root application
- External Secrets Operator
- GCS bucket for Terraform state

**Manual Step Required**: Create GitHub credentials in Secret Manager for ArgoCD:

```bash
PROJECT_ID=$(terraform output -json | jq -r '.global.value.project_id')

echo '{
  "url": "https://github.com/your-org/gcp-hcp-infra.git",
  "username": "your-github-username",
  "password": "github_pat_..."
}' | gcloud secrets create argocd-repo-creds \
  --project=$PROJECT_ID \
  --data-file=- \
  --replication-policy="automatic"
```

**Example Terraform Config**: See [terraform-examples/integration-global.tf](../terraform-examples/integration-global.tf) for complete example.

### 2. Regional Infrastructure

Deploy regional GKE clusters (one per sector/region):

```bash
# Generate infrastructure ID and create config
./scripts/infra.py new region integration main us-central1

# Or manually from template
cd terraform/config/region/integration/main/us-central1
terraform init && terraform apply
```

**Creates**:
- Regional GCP project
- GKE cluster (Standard or Autopilot)
- VPC network with private subnets
- Fleet registration
- Config Sync configuration
- Cluster metadata in Secret Manager

**What Happens After Apply** (Autonomous Bootstrap):
1. GKE cluster registers in Fleet automatically
2. **Fleet Config Sync** pulls bootstrap manifests from Git
3. ArgoCD and External Secrets Operator are deployed automatically
4. ExternalSecret pulls cluster metadata from Secret Manager
5. ArgoCD root application starts managing all apps

**Example Terraform Config**: See [terraform-examples/integration-regional-cluster.tf](../terraform-examples/integration-regional-cluster.tf) for complete example.

### 3. Management Clusters

Deploy Hypershift-hosting clusters (multiple per region):

```bash
./scripts/infra.py new management-cluster integration main us-central1

cd terraform/config/management-cluster/integration/main/us-central1/mgmt-1
terraform init && terraform apply
```

**Creates**:
- Management cluster GCP project
- GKE cluster for Hypershift
- PSC (Private Service Connect) subnets
- Workload Identity bindings
- Fleet registration (cross-project)

**Autonomous Bootstrap** (same as regional clusters):
- Fleet Config Sync deploys ArgoCD
- Hypershift operator deployed via ArgoCD
- Ready to host customer control planes

---

## Fleet Config Sync: GCP's Unique Advantage

### What is Fleet Config Sync?

Fleet Config Sync is a GCP-native GitOps controller that enables **autonomous cluster bootstrapping** without external CI/CD systems.

### How It Works

```
Terraform Apply → GKE Cluster Created → Fleet Registration
                                              ↓
                                    Config Sync Enabled
                                              ↓
                      Pulls from Git (argocd/bootstrap/)
                                              ↓
                    Deploys: ArgoCD + External Secrets
                                              ↓
                          ArgoCD Takes Over (GitOps)
```

### Benefits

- ✅ **No GitHub Actions workflows needed** for cluster bootstrap
- ✅ **Autonomous** - clusters self-configure from Git
- ✅ **Declarative** - entire bootstrap defined in Git
- ✅ **Auditable** - all sync operations logged in GCP
- ✅ **No cross-cluster network access** required

### Configuration Example

```hcl
# In Terraform (modules/region/main.tf)
resource "google_gke_hub_feature_membership" "configmanagement" {
  location   = "global"
  feature    = google_gke_hub_feature.configmanagement.name
  membership = google_gke_hub_membership.cluster.membership_id

  configmanagement {
    version = "1.17.0"

    config_sync {
      source_format = "unstructured"
      git {
        sync_repo   = "https://github.com/org/gcp-hcp-infra.git"
        sync_branch = "main"
        policy_dir  = "argocd/bootstrap"
        secret_type = "gcpserviceaccount"
      }
    }
  }
}
```

---

## GCP Workload Identity for Secret Access

GCP HCP uses **Workload Identity** for secure, keyless authentication (no service account keys).

### Setup (handled by Terraform)

```hcl
# Create GCP service account
resource "google_service_account" "app" {
  account_id = "app-service-account"
  project    = var.project_id
}

# Grant Secret Manager access
resource "google_secret_manager_secret_iam_member" "app" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# Bind Kubernetes SA to GCP SA
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/app]"
}
```

### Kubernetes Side

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app
  namespace: default
  annotations:
    iam.gke.io/gcp-service-account: app-service-account@project-id.iam.gserviceaccount.com
```

Pods using this ServiceAccount automatically get GCP credentials via Workload Identity.

**For detailed secret management setup**, see [secret-manager-integration.md](secret-manager-integration.md).

---

## Directory Structure for GCP HCP

```
gcp-hcp-infra/
├── terraform/
│   ├── modules/
│   │   ├── global/              # Environment-level control plane
│   │   ├── region/              # Regional GKE deployments
│   │   ├── management-cluster/  # Hypershift hosting clusters
│   │   └── workflows/           # Cloud Workflows for operations
│   └── config/
│       ├── global/
│       │   └── {env}/{sector}/{region}/main.tf
│       ├── region/
│       │   └── {env}/{sector}/{region}/main.tf
│       └── management-cluster/
│           └── {env}/{sector}/{region}/{cluster-name}/main.tf
├── argocd/
│   ├── config/                  # Source manifests
│   │   ├── global/              # Apps deployed FROM global
│   │   └── region/              # Apps deployed ON region/mgmt
│   ├── rendered/                # Helm charts (auto-generated)
│   └── bootstrap/               # Fleet Config Sync bootstrap manifests
└── helm/
    └── charts/                  # Custom Helm charts
```

---

## Comparison: ROSA vs GCP HCP Deployment

| **Aspect** | **ROSA (AWS)** | **GCP HCP (GCP)** |
|------------|----------------|-------------------|
| **IaC Execution** | GitHub Actions workflows | Manual `terraform apply` or Cloud Build |
| **CI/CD Platform** | GitHub Actions (required) | Optional (Fleet Config Sync handles bootstrap) |
| **Cluster Bootstrap** | ECS task runs ArgoCD install | Fleet Config Sync (autonomous from Git) |
| **State Management** | S3 + DynamoDB (explicit locking) | GCS (built-in locking) |
| **Authentication** | AWS OIDC via GitHub | `gcloud auth` or Workload Identity Federation |
| **Secret Management** | HashiCorp Vault (external) | GCP Secret Manager (native) |
| **Autonomous Bootstrap** | ❌ No (requires GitHub Actions) | ✅ Yes (Fleet Config Sync) |
| **Workflow Complexity** | Higher (multiple workflows) | Lower (Terraform + Fleet) |
| **Operational Overhead** | Medium (GitHub + Vault + ECS) | Low (Terraform + Fleet + Secret Manager) |

---

## Security Best Practices

1. **Use Workload Identity** for all GCP authentication (no service account keys)
2. **Enable GCS bucket versioning** for Terraform state
3. **Use separate GCP projects** for different environments and clusters
4. **Enable Secret Manager audit logging** for compliance
5. **Restrict Secret Manager IAM** to least-privilege per application
6. **Use private GKE clusters** with Cloud NAT for outbound access
7. **Enable GKE Workload Identity** on all clusters
8. **Use Config Connector** for declarative GCP resource management
9. **Enable Cloud Audit Logs** for all API operations
10. **Use GCP Organizations** with folder-based hierarchy for multi-environment management

---

## Troubleshooting

### Common Issues

| **Issue** | **Cause** | **Solution** |
|-----------|-----------|--------------|
| `Fleet Config Sync not syncing` | Wrong Git repo or credentials | Check `config-management-system` namespace logs, verify Secret Manager secret |
| `ArgoCD not bootstrapping` | Fleet Config Sync failed | Run `gcloud beta container fleet config-management status` to check sync status |
| `Workload Identity not working` | IAM binding missing | Verify `iam.workloadIdentityUser` binding on GCP service account |
| `Cannot access GKE cluster` | Missing IAM permissions | Grant `roles/container.developer` to your user |
| `Terraform state locked` | Previous apply didn't complete | GCS locks expire after 15 minutes automatically |
| `External Secrets not syncing` | Secret Manager permissions | Check Workload Identity binding and Secret Manager IAM policies |

---

## Additional Resources

- **[GCP HCP Repository](https://github.com/openshift-online/gcp-hcp-infra)** - Full source code and modules
- **[Official Deployment Guide](https://github.com/openshift-online/gcp-hcp-infra/blob/main/docs/DEPLOYMENT_GUIDE.md)** - Complete deployment walkthrough
- **[Secret Manager Integration](secret-manager-integration.md)** - Detailed GCP Secret Manager setup
- **[Terraform Examples](../terraform-examples/)** - Sample configurations for integration and production
- **[Infrastructure Comparison](../../infrastructure-comparison.md)** - ARO-HCP vs ROSA vs GCP HCP comparison
- **[README.md](README.md)** - Quick reference and getting started

### Related Documentation

- **[GCP Secret Manager Docs](https://cloud.google.com/secret-manager/docs)** - Official GCP documentation
- **[External Secrets Operator](https://external-secrets.io/)** - ESO documentation
- **[Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)** - GCP Workload Identity guide
- **[Fleet Config Sync](https://cloud.google.com/kubernetes-engine/docs/add-on/config-sync/overview)** - Fleet Config Sync documentation
