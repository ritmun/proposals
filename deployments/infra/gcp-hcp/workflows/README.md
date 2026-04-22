# GCP HCP Workflows

## Why This Directory is Empty (or Contains Only Cloud Build Examples)

This proposal document shows how GCP HCP **could** be deployed using different approaches than the proposed ROSA HCP GitHub Actions pattern:

### GCP HCP Deployment Methods (Proposed)

1. **Manual Terraform Execution** (Primary Method)
   ```bash
   cd terraform/config/global/integration/main/us-central1
   terraform init
   terraform apply
   ```

2. **Cloud Build** (Optional CI/CD Alternative)
   - GCP's native CI/CD service
   - Can be configured to trigger on Git commits
   - Example Cloud Build configuration would go here if adopted
   - **Alternative to GitHub Actions** for GCP-native automation

3. **Fleet Config Sync** (Autonomous Bootstrap - GCP's Unique Advantage)
   - After `terraform apply` creates a GKE cluster, Fleet Config Sync automatically:
     - Registers cluster in Fleet
     - Pulls bootstrap manifests from Git
     - Deploys ArgoCD and External Secrets Operator
   - **No external CI/CD required for cluster bootstrap**

### Key Difference from Proposed ROSA HCP Pattern

| **Platform** | **Proposed Deployment Automation** | **Bootstrap Method** |
|--------------|-----------------------------------|----------------------|
| **ROSA HCP** | GitHub Actions workflows (proposed, following ARO-HCP) | ECS task runs kubectl/helm (proposed) |
| **GCP HCP** | Manual terraform or Cloud Build (proposed alternatives) | Fleet Config Sync (autonomous - GCP-native) |

### Cloud Build Workflows (Optional Alternative)

If you want to automate GCP HCP deployments with Cloud Build instead of manual Terraform, example workflows are provided:

- **[cloudbuild-global.yaml](cloudbuild-global.yaml)** - Global infrastructure deployment
  - Automates `terraform init/plan/apply` for global clusters
  - Creates GKE Autopilot, ArgoCD, External Secrets
  - Stores outputs as GCS artifacts

- **[cloudbuild-regional.yaml](cloudbuild-regional.yaml)** - Regional cluster deployment
  - Automates regional GKE cluster creation
  - Waits for Fleet Config Sync to bootstrap ArgoCD
  - Verifies ArgoCD is running

- **[cloudbuild-management.yaml](cloudbuild-management.yaml)** - Management cluster deployment
  - Automates management cluster creation for Hypershift
  - Cross-project Fleet registration
  - Verifies Hypershift operator deployment

**Setup**:
```bash
# Create Cloud Build trigger
gcloud builds triggers create github \
  --repo-name=gcp-hcp-infra \
  --repo-owner=your-org \
  --branch-pattern=^main$ \
  --build-config=gcp-hcp/workflows/cloudbuild-global.yaml \
  --included-files=terraform/config/global/**

# Grant Cloud Build service account permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=serviceAccount:cloud-build@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/compute.admin
```

### Resources

- **[GCP Deployment Guide](../docs/deployment-guide.md)** - Manual deployment instructions
- **[Cloud Build Documentation](https://cloud.google.com/build/docs)** - GCP's CI/CD service
- **[Fleet Config Sync](https://cloud.google.com/kubernetes-engine/docs/add-on/config-sync/overview)** - Autonomous cluster bootstrap
