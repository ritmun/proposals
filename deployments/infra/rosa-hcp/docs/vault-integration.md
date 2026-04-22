# HashiCorp Vault Integration for ROSA HCP

## Overview

This guide provides detailed configuration examples for integrating HashiCorp Vault with ROSA HCP for application runtime secret management.

**HashiCorp Vault** is used for all **application runtime secrets** in ROSA HCP deployments, including:

- Database credentials (PostgreSQL, DynamoDB access)
- API keys and tokens
- TLS certificates and private keys
- Service-to-service authentication credentials
- Third-party integration secrets

> **Note**: This is separate from GitHub Secrets, which are used only for CI/CD pipeline configuration. See [infrastructure-comparison.md](../../infrastructure-comparison.md#4-required-github-secrets) for details.

---

## Secret Types Comparison

| **Secret Type** | **Storage** | **Use Case** | **Access Method** |
|----------------|------------|--------------|-------------------|
| **Infrastructure/CI** | GitHub Secrets (UI) | Deployment pipeline config, AWS account IDs, IAM role ARNs | GitHub Actions workflows via `${{ secrets.NAME }}` |
| **Application Runtime** | HashiCorp Vault | Database passwords, API keys, certificates | External Secrets Operator or Vault Agent Injector |

---

## Integration Patterns

ROSA HCP supports two primary patterns for Vault integration:

### 1. External Secrets Operator (ESO) - **Recommended**

**Best for**: Kubernetes-native secret management with automatic sync

External Secrets Operator pulls secrets from Vault and creates native Kubernetes Secrets.

**Advantages**:
- ✅ Kubernetes-native (uses `ExternalSecret` CRDs)
- ✅ Automatic secret rotation
- ✅ Multi-backend support (Vault, AWS Secrets Manager, etc.)
- ✅ Centralized secret management
- ✅ Works with existing applications expecting `Secret` objects

**Architecture**:
```
Vault (External) → ESO Controller → ExternalSecret CR → Kubernetes Secret → Pod
```

### 2. Vault Agent Injector

**Best for**: Direct Vault integration with sidecar injection

Injects a Vault Agent sidecar that fetches secrets directly.

**Advantages**:
- ✅ Secrets never stored in Kubernetes
- ✅ Direct Vault authentication
- ✅ Template-based secret rendering
- ✅ Automatic secret renewal

**Architecture**:
```
Pod (with annotations) → Vault Agent Sidecar → Vault (External) → Secrets mounted as files
```

---

## Authentication Methods

### Option 1: AWS IAM Authentication (Recommended for ROSA)

Vault authenticates pods using AWS IAM roles (via IRSA - IAM Roles for Service Accounts).

**Setup**:

1. **Enable AWS auth in Vault**:
```bash
vault auth enable aws
```

2. **Configure Vault AWS auth backend**:
```bash
vault write auth/aws/config/client \
  iam_endpoint="https://iam.amazonaws.com" \
  sts_endpoint="https://sts.amazonaws.com"
```

3. **Create Vault role for ROSA pods**:
```bash
vault write auth/aws/role/rosa-app \
  auth_type=iam \
  bound_iam_principal_arn="arn:aws:iam::123456789012:role/rosa-app-role" \
  policies="rosa-app-policy" \
  ttl=1h
```

4. **Attach IAM role to Kubernetes ServiceAccount**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rosa-app
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/rosa-app-role
```

### Option 2: Kubernetes Authentication

Vault authenticates pods using Kubernetes ServiceAccount tokens.

**Setup**:

1. **Enable Kubernetes auth in Vault**:
```bash
vault auth enable kubernetes
```

2. **Configure Vault Kubernetes auth**:
```bash
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

3. **Create Vault role**:
```bash
vault write auth/kubernetes/role/rosa-app \
  bound_service_account_names=rosa-app \
  bound_service_account_namespaces=default \
  policies=rosa-app-policy \
  ttl=1h
```

---

## External Secrets Operator (ESO) - Example Configuration

### 1. Install External Secrets Operator

**Via Helm**:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace
```

**Or via ArgoCD ApplicationSet** (recommended for GitOps):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://charts.external-secrets.io
    chart: external-secrets
    targetRevision: 0.9.11
  destination:
    server: https://kubernetes.default.svc
    namespace: external-secrets-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2. Create SecretStore (Vault Backend)

**Using AWS IAM Auth**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      server: "https://vault.example.com:8200"
      path: "secret"  # KV v2 mount path
      version: "v2"
      auth:
        aws:
          region: us-east-1
          role: rosa-app  # Vault role name
          secretRef:
            accessKeyID:
              name: aws-creds
              key: access-key-id
            secretAccessKey:
              name: aws-creds
              key: secret-access-key
```

**Using Kubernetes Auth**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      server: "https://vault.example.com:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "rosa-app"
          serviceAccountRef:
            name: "rosa-app"
```

### 3. Create ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: default
spec:
  refreshInterval: 1h  # Sync every hour
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: database-credentials  # Name of the Kubernetes Secret to create
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: database/postgres  # Path in Vault: secret/data/database/postgres
```

**Or with specific key mapping**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-config
  namespace: default
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: app-config
    creationPolicy: Owner
  data:
    - secretKey: db-password       # Key in Kubernetes Secret
      remoteRef:
        key: database/postgres     # Vault path
        property: password         # Field in Vault secret
    - secretKey: api-key
      remoteRef:
        key: api/external-service
        property: key
```

### 4. Use the Secret in a Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rosa-app
  namespace: default
spec:
  serviceAccountName: rosa-app
  containers:
    - name: app
      image: rosa-app:latest
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
```

---

## Vault Agent Injector - Example Configuration

### 1. Install Vault Agent Injector

**Via Helm**:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --set "injector.enabled=true" \
  --set "injector.externalVaultAddr=https://vault.example.com:8200" \
  -n vault-system \
  --create-namespace
```

### 2. Annotate Pods for Injection

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rosa-app
  namespace: default
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "rosa-app"
    vault.hashicorp.com/agent-inject-secret-database: "secret/data/database/postgres"
    vault.hashicorp.com/agent-inject-template-database: |
      {{- with secret "secret/data/database/postgres" -}}
      export DB_HOST="{{ .Data.data.host }}"
      export DB_USER="{{ .Data.data.username }}"
      export DB_PASSWORD="{{ .Data.data.password }}"
      {{- end }}
spec:
  serviceAccountName: rosa-app
  containers:
    - name: app
      image: rosa-app:latest
      command: ["/bin/sh"]
      args:
        - -c
        - |
          source /vault/secrets/database
          ./start-app.sh
```

**Secrets will be available at**: `/vault/secrets/database`

---

## Vault Policy Example

**`rosa-app-policy.hcl`**:
```hcl
# Read database credentials
path "secret/data/database/*" {
  capabilities = ["read", "list"]
}

# Read API keys
path "secret/data/api/*" {
  capabilities = ["read"]
}

# Allow token renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow token lookup
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
```

**Apply the policy**:
```bash
vault policy write rosa-app-policy rosa-app-policy.hcl
```

---

## Terraform Configuration for Vault Integration

**`terraform/vault-config/main.tf`**:
```hcl
# Configure Vault provider
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
  }
}

provider "vault" {
  address = var.vault_address
}

# Enable AWS auth backend
resource "vault_auth_backend" "aws" {
  type = "aws"
}

# Configure AWS auth
resource "vault_aws_auth_backend_client" "rosa" {
  backend = vault_auth_backend.aws.path
}

# Create Vault policy for ROSA app
resource "vault_policy" "rosa_app" {
  name   = "rosa-app-policy"
  policy = file("${path.module}/policies/rosa-app-policy.hcl")
}

# Create Vault role for AWS IAM authentication
resource "vault_aws_auth_backend_role" "rosa_app" {
  backend                  = vault_auth_backend.aws.path
  role                     = "rosa-app"
  auth_type                = "iam"
  bound_iam_principal_arns = [var.rosa_app_iam_role_arn]
  token_policies           = [vault_policy.rosa_app.name]
  token_ttl                = 3600
  token_max_ttl            = 7200
}

# Store database credentials in Vault
resource "vault_kv_secret_v2" "database" {
  mount = "secret"
  name  = "database/postgres"

  data_json = jsonencode({
    host     = module.rds.endpoint
    port     = 5432
    username = "app_user"
    password = random_password.db_password.result
    database = "rosa_db"
  })
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}
```

---

## ClusterSecretStore for Multi-Namespace Access

For secrets needed across multiple namespaces:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend-global
spec:
  provider:
    vault:
      server: "https://vault.example.com:8200"
      path: "secret"
      version: "v2"
      auth:
        aws:
          region: us-east-1
          role: rosa-platform
```

**Reference from any namespace**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: shared-credentials
  namespace: app-namespace
spec:
  secretStoreRef:
    name: vault-backend-global
    kind: ClusterSecretStore
  # ... rest of config
```

---

## Best Practices

1. **Use External Secrets Operator for most use cases** - simpler, Kubernetes-native
2. **Prefer AWS IAM authentication** for ROSA (leverages IRSA, no long-lived tokens)
3. **Use ClusterSecretStore** for shared secrets (monitoring, logging, etc.)
4. **Set appropriate refresh intervals** (15m for frequently-rotated, 1h for static)
5. **Enable secret rotation** in Vault and use short TTLs
6. **Use Vault namespaces** to isolate environments (dev/int/stage/prod)
7. **Audit Vault access** - enable Vault audit logging
8. **Use Terraform to manage Vault configuration** (auth backends, policies, roles)
9. **Never commit Vault tokens** to Git (use GitHub Secrets for Vault root token if needed)
10. **Test secret rotation** - ensure apps handle credential updates gracefully

---

## Troubleshooting Vault Integration

| **Issue** | **Cause** | **Solution** |
|-----------|-----------|--------------|
| `Error: secret not synced` (ESO) | Vault path incorrect or no permissions | Check Vault path and policy, verify with `vault read secret/data/path` |
| `Error: authentication failed` | IAM role not trusted by Vault | Verify `bound_iam_principal_arn` in Vault role matches pod's IAM role |
| `Error: token expired` | TTL too short | Increase `token_ttl` in Vault role or reduce ESO `refreshInterval` |
| `Sidecar injection not working` (Agent) | Missing annotations or injector not running | Check pod annotations and verify Vault Agent Injector deployment |
| `Secret rotation not working` | ESO refresh interval too long | Reduce `refreshInterval` in ExternalSecret spec |

---

## Additional Resources

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Agent Injector Guide](https://www.vaultproject.io/docs/platform/k8s/injector)
- [AWS IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)