# GCP Secret Manager Integration for GCP HCP

## Overview

This guide provides detailed configuration examples for integrating GCP Secret Manager with GCP HCP for application runtime secret management.

**GCP Secret Manager** is used for all **application runtime secrets** in GCP HCP deployments, including:

- Database credentials (Cloud SQL PostgreSQL)
- API keys and tokens
- TLS certificates and private keys
- Service-to-service authentication credentials
- Third-party integration secrets
- Container pull secrets

> **Note**: This is separate from GitHub Secrets, which are used only for CI/CD pipeline configuration. See [infrastructure-comparison.md](../infrastructure-comparison.md#application-secret-management) for the comparison between platforms.

---

## Secret Types Comparison

| **Secret Type** | **Storage** | **Use Case** | **Access Method** |
|----------------|------------|--------------|-------------------|
| **Infrastructure/CI** | GitHub Secrets (UI) | Deployment pipeline config, GCP project IDs, folder IDs | GitHub Actions workflows (if used) via `${{ secrets.NAME }}` |
| **Application Runtime** | GCP Secret Manager | Database passwords, API keys, certificates, pull secrets | External Secrets Operator with Workload Identity |

---

## Integration Architecture

GCP HCP uses **External Secrets Operator (ESO)** with native GCP Secret Manager backend:

```
GCP Secret Manager → External Secrets Operator → Kubernetes Secret → Pod
         ↑                       ↑
   Workload Identity      ClusterSecretStore/SecretStore
```

**Key Components**:
- **GCP Secret Manager**: Native GCP secret storage with versioning and IAM integration
- **External Secrets Operator**: Kubernetes controller that syncs secrets from Secret Manager
- **Workload Identity**: Keyless authentication (no service account keys)
- **ClusterSecretStore**: Cluster-wide secret backend configuration
- **ExternalSecret**: Custom resource defining which secrets to sync

---

## Authentication: Workload Identity

GCP HCP uses **Workload Identity** for secure, keyless authentication (no service account keys ever needed).

### How It Works

```
Pod (with ServiceAccount) → GKE Workload Identity → GCP Service Account → Secret Manager
```

**Setup** (handled by Terraform):

```hcl
# 1. Create GCP service account
resource "google_service_account" "external_secrets" {
  account_id   = "external-secrets"
  display_name = "External Secrets Operator"
  project      = var.project_id
}

# 2. Grant Secret Manager access
resource "google_project_iam_member" "external_secrets_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}

# 3. Bind Kubernetes SA to GCP SA via Workload Identity
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets-system/external-secrets]"
}
```

**Kubernetes Side**:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: external-secrets-system
  annotations:
    iam.gke.io/gcp-service-account: external-secrets@PROJECT_ID.iam.gserviceaccount.com
```

---

## External Secrets Operator - Configuration

### 1. Install External Secrets Operator

**Via Terraform** (preferred - included in GCP HCP modules):

External Secrets Operator is automatically deployed via Fleet Config Sync bootstrap manifests.

**Manual Helm Installation** (for testing):

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

### 2. Create ClusterSecretStore (Project-Scoped)

**For secrets in the same GCP project as the cluster**:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: PROJECT_ID  # Auto-detected if omitted
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: my-cluster
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets-system
```

**Simplified version** (uses cluster's own project):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      auth:
        workloadIdentity:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets-system
```

### 3. Create ClusterSecretStore (Cross-Project)

**For secrets in a different GCP project** (e.g., management clusters accessing global project secrets):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: global-secret-manager
spec:
  provider:
    gcpsm:
      projectID: gcp-hcp-int-global  # Explicit global project ID
      auth:
        workloadIdentity:
          serviceAccountRef:
            name: global-secret-store  # Cross-project SA
            namespace: external-secrets-system
```

**Required IAM Binding** (in global project):

```hcl
# Grant management cluster's Workload Identity access to global secrets
resource "google_secret_manager_secret_iam_member" "mgmt_cluster_access" {
  project   = var.global_project_id
  secret_id = google_secret_manager_secret.hypershift_pull_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.mgmt_project_id}.svc.id.goog[external-secrets-system/external-secrets]"
}
```

### 4. Create ExternalSecret

**Basic Example** (fetch entire secret):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: default
spec:
  refreshInterval: 1h  # Sync every hour
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: database-credentials  # Name of Kubernetes Secret to create
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: database-postgres  # Secret Manager secret name
```

**With Specific Key Mapping**:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-config
  namespace: default
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: app-config
    creationPolicy: Owner
  data:
    - secretKey: db-password       # Key in Kubernetes Secret
      remoteRef:
        key: database-postgres     # Secret Manager secret name
        property: password         # JSON field (if secret is JSON)
    - secretKey: api-key
      remoteRef:
        key: external-api-key
```

**With Secret Version Pinning**:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-config-pinned
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: app-config-pinned
  data:
    - secretKey: db-password
      remoteRef:
        key: database-postgres
        version: "3"  # Pin to specific version
```

### 5. Use the Secret in a Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: default
spec:
  serviceAccountName: app-service-account
  containers:
    - name: app
      image: app:latest
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: database-credentials  # Created by ESO
              key: password
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-config
              key: api-key
      volumeMounts:
        - name: certs
          mountPath: /etc/certs
          readOnly: true
  volumes:
    - name: certs
      secret:
        secretName: tls-certificates  # Also created by ESO
```

---

## Secret Manager Secret Creation

### Via Terraform

```hcl
# Create the secret
resource "google_secret_manager_secret" "database_password" {
  secret_id = "database-postgres-password"
  project   = var.project_id

  replication {
    auto {}  # Auto-replicate to all regions
  }

  # Optional: Single-region replication
  # replication {
  #   user_managed {
  #     replicas {
  #       location = "us-central1"
  #     }
  #   }
  # }
}

# Add the secret value
resource "google_secret_manager_secret_version" "database_password" {
  secret = google_secret_manager_secret.database_password.id

  secret_data = random_password.db_password.result
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Grant access to specific service account
resource "google_secret_manager_secret_iam_member" "app_access" {
  secret_id = google_secret_manager_secret.database_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_id}.svc.id.goog[default/app-service-account]"
}
```

### Via gcloud CLI

```bash
# Create secret
echo -n "my-secret-value" | gcloud secrets create my-secret \
  --project=PROJECT_ID \
  --data-file=- \
  --replication-policy=automatic

# Update secret (creates new version)
echo -n "new-secret-value" | gcloud secrets versions add my-secret \
  --project=PROJECT_ID \
  --data-file=-

# Create JSON secret
cat <<EOF | gcloud secrets create database-config \
  --project=PROJECT_ID \
  --data-file=-
{
  "host": "10.0.0.5",
  "port": 5432,
  "username": "app_user",
  "password": "$(openssl rand -base64 32)"
}
EOF

# Grant access
gcloud secrets add-iam-policy-binding my-secret \
  --project=PROJECT_ID \
  --role=roles/secretmanager.secretAccessor \
  --member="serviceAccount:PROJECT_ID.svc.id.goog[default/app]"
```

---

## Real-World Example: Hypershift Pull Secret

This is how GCP HCP manages container pull secrets for Hypershift operator.

### 1. Secret in Global Project

**Terraform** (`terraform/modules/global/secrets.tf`):

```hcl
resource "google_secret_manager_secret" "hypershift_pull_secret" {
  secret_id = "hypershift-pull-secret"
  project   = module.project.project_id

  replication {
    auto {}
  }
}

# Manual step: Add the actual pull secret value
# gcloud secrets versions add hypershift-pull-secret --data-file=pull-secret.json
```

### 2. Cross-Project IAM Binding

**Terraform** (`terraform/modules/management-cluster/secrets.tf`):

```hcl
# Grant management cluster's ESO access to global project secret
resource "google_secret_manager_secret_iam_member" "hypershift_pull_secret" {
  project   = var.global_project_id
  secret_id = "hypershift-pull-secret"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.project.project_id}.svc.id.goog[external-secrets-system/external-secrets]"
}
```

### 3. SecretStore in Management Cluster

**ArgoCD Config** (`argocd/config/management-cluster/global-cluster-secret-store/template.yaml`):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: {{ .Values.global_project_id }}
      auth:
        workloadIdentity:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets-system
```

### 4. ExternalSecret for Hypershift

**Kustomize** (`kustomize/hypershift/secrets.yaml`):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: pull-secret
  namespace: hypershift
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: global-gcp-secret-manager
    kind: SecretStore  # Namespace-scoped
  target:
    name: pull-secret
    creationPolicy: Owner
  data:
    - secretKey: .dockerconfigjson
      remoteRef:
        key: hypershift-pull-secret
```

---

## Secret Rotation

### Automatic Rotation

External Secrets Operator handles rotation automatically:

1. Set `refreshInterval` in ExternalSecret (e.g., `15m`, `1h`)
2. ESO polls Secret Manager periodically
3. When a new version is detected, Kubernetes Secret is updated
4. Pods with mounted secrets get updates within `kubelet.syncPeriod` (default: 1 minute)

### Manual Rotation

```bash
# Create new secret version
echo -n "new-value" | gcloud secrets versions add my-secret \
  --project=PROJECT_ID \
  --data-file=-

# Destroy old versions (optional)
gcloud secrets versions destroy VERSION_NUMBER \
  --secret=my-secret \
  --project=PROJECT_ID
```

### Application Handling

**Environment Variables**: Apps must restart to pick up new values
**Volume Mounts**: Updated automatically (within ~60s)

**Best Practice**: Use volume mounts for secrets that need automatic rotation:

```yaml
containers:
  - name: app
    volumeMounts:
      - name: secrets
        mountPath: /var/secrets
        readOnly: true
volumes:
  - name: secrets
    secret:
      secretName: app-secrets
```

---

## Best Practices

1. **Use Workload Identity exclusively** - Never create service account keys
2. **Enable automatic replication** for high availability
3. **Use shortest necessary `refreshInterval`** (balance freshness vs API costs)
4. **Pin critical secrets to specific versions** in production
5. **Use ClusterSecretStore for shared secrets** (monitoring, logging, etc.)
6. **Use namespace-scoped SecretStore** for team-specific secrets
7. **Enable Secret Manager audit logging** via Cloud Audit Logs
8. **Use IAM conditions** for time-based or attribute-based access control
9. **Rotate secrets regularly** and test rotation in non-prod first
10. **Use structured secrets (JSON)** for complex configurations

---

## Security Best Practices

1. **Least Privilege IAM**:
   - Grant `roles/secretmanager.secretAccessor` per-secret, not project-wide
   - Use IAM conditions to restrict access further

2. **Audit Logging**:
   ```hcl
   # Enable Data Access audit logs for Secret Manager
   resource "google_project_iam_audit_config" "secret_manager" {
     project = var.project_id
     service = "secretmanager.googleapis.com"

     audit_log_config {
       log_type = "DATA_READ"
     }
     audit_log_config {
       log_type = "DATA_WRITE"
     }
   }
   ```

3. **Secret Versioning**:
   - Never delete the latest version
   - Keep at least 2 versions for rollback
   - Use `terraform_data` to force version creation on value changes

4. **Network Security**:
   - Use VPC Service Controls to restrict Secret Manager API access
   - Enable Private Google Access on subnets

---

## Troubleshooting

| **Issue** | **Cause** | **Solution** |
|-----------|-----------|--------------|
| `Error: secret not synced` | Secret Manager secret doesn't exist or wrong project | Verify secret exists with `gcloud secrets describe SECRET_NAME --project=PROJECT_ID` |
| `Error: permission denied` | Missing IAM binding | Check Workload Identity binding and `secretmanager.secretAccessor` role |
| `Error: workload identity not configured` | Missing GKE annotation on ServiceAccount | Add `iam.gke.io/gcp-service-account` annotation to K8s ServiceAccount |
| `Secret value is empty` | Secret has no versions | Add a version with `gcloud secrets versions add` |
| `Cross-project access fails` | IAM binding in wrong project | Ensure IAM binding is in the SECRET's project, not the cluster's project |
| `ExternalSecret stuck in "SecretSynced=False"` | ESO can't reach Secret Manager API | Check VPC firewall rules, Private Google Access, and VPC Service Controls |

---

## Comparison with HashiCorp Vault (ROSA/ARO-HCP)

| **Aspect** | **GCP Secret Manager (GCP HCP)** | **HashiCorp Vault (ROSA/ARO-HCP)** |
|------------|----------------------------------|-------------------------------------|
| **Deployment** | Managed GCP service | External server (self-hosted or HCP) |
| **Authentication** | Workload Identity (native) | AWS IAM (IRSA) or Azure Managed Identity |
| **Operational Overhead** | None (fully managed) | Medium (manage Vault server, HA, upgrades) |
| **Secret Versioning** | Built-in automatic versioning | Manual versioning or KV v2 engine |
| **Audit Logging** | Cloud Audit Logs (native) | Vault audit logs (separate system) |
| **Cost** | Pay per operation + storage | Vault license + infrastructure costs |
| **Rotation** | Automatic via ESO `refreshInterval` | Automatic via ESO or Vault Agent |
| **Multi-Cloud** | GCP only | Works across clouds |
| **Learning Curve** | Low (GCP IAM concepts) | Higher (Vault-specific concepts) |

---

## Additional Resources

**GCP Documentation**:
- [Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [Workload Identity Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Best Practices for Secret Manager](https://cloud.google.com/secret-manager/docs/best-practices)

**External Secrets Operator**:
- [ESO Documentation](https://external-secrets.io/)
- [GCP Secret Manager Provider](https://external-secrets.io/latest/provider/google-secrets-manager/)

**GCP HCP Repository**:
- [Terraform Modules](https://github.com/openshift-online/gcp-hcp-infra/tree/main/terraform/modules)
- [External Secrets Config](https://github.com/openshift-online/gcp-hcp-infra/tree/main/argocd/config/management-cluster/global-cluster-secret-store)
- [Deployment Guide](https://github.com/openshift-online/gcp-hcp-infra/blob/main/docs/DEPLOYMENT_GUIDE.md)
