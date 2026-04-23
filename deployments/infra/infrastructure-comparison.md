# Infrastructure Service Comparison: ARO-HCP (Azure) vs ROSA HCP (AWS) vs GCP HCP (GCP)

> **Document Type**: Proposal and Reference Comparison
> **Purpose**: Propose ROSA HCP and  GCP HCP infra deployment following ARO-HCP pattern

## Overview

This document provides a comprehensive proposed deployment approaches for Hosted Control Plane (HCP) infrastructure for Red Hat OpenShift based on the ARO-HCP model:

- **ARO-HCP** - Azure Red Hat OpenShift Hosted Control Planes (Production implementation - reference pattern)
- **ROSA HCP** - Red Hat OpenShift Service on AWS Hosted Control Planes (Proposed GitHub Actions pattern following ARO-HCP)
- **GCP HCP** - Google Cloud Platform Hypershift Control Plane (Proposed Fleet Config Sync pattern - alternative approach)

## Table of Contents

- [Key Architectural Differences](#key-architectural-differences)
- [Service Parity Matrix](#service-parity-matrix)
- [Deployment Workflow Comparison](#deployment-workflow-comparison)
- [Application Secret Management Comparison](#application-secret-management)
- [ROSA HCP-Specific Deployment (Proposed)](#rosa-hcp-specific-deployment-proposed)
- [GCP HCP-Specific Deployment (Proposed)](#gcp-hcp-specific-deployment-proposed)

**Platform-Specific Resources**:
- 📘 **ARO-HCP**: [Azure ARO-HCP Reference Repository](https://github.com/Azure/ARO-HCP) - Bicep templates and workflows
- 📘 **ROSA HCP**: [ROSA HCP Documentation](rosa-hcp/) - Complete deployment resources
  - [GitHub Actions Workflows](rosa-hcp/workflows/) - CI/CD automation for ROSA HCP
  - [Deployment Guide](rosa-hcp/docs/deployment-guide.md) - Complete deployment instructions
  - [Vault Integration Guide](rosa-hcp/docs/vault-integration.md) - HashiCorp Vault setup
  - [Terraform Examples](rosa-hcp/terraform-examples/tfvars/) - Sample tfvars files for dev and prod
  - [ROSA Regional Platform Repository](https://github.com/openshift-online/rosa-regional-platform) - Terraform modules and infrastructure code
- 📘 **GCP HCP**: [GCP HCP Documentation](gcp-hcp/) - Complete deployment resources
  - [GitHub Actions Workflows](gcp-hcp/workflows/) - Why GCP HCP doesn't use GitHub Actions
  - [Deployment Guide](gcp-hcp/docs/deployment-guide.md) - Manual Terraform and Fleet Config Sync
  - [Secret Manager Integration Guide](gcp-hcp/docs/secret-manager-integration.md) - GCP Secret Manager with External Secrets Operator
  - [Terraform Examples](gcp-hcp/terraform-examples/) - Sample configs for integration and production
  - [GCP HCP Repository](https://github.com/openshift-online/gcp-hcp-infra) - Full source code and modules

---

## Key Architectural Differences

| **Aspect** | **ARO-HCP (Azure)** | **ROSA HCP (AWS)** | **GCP HCP (GCP)** |
|------------|---------------------|-------------------|-------------------|
| **Account/Project Model** | Single/few Azure subscriptions with resource groups | Multi-account AWS architecture with dedicated accounts per cluster | GCP folder-based hierarchy with dedicated projects per environment |
| **Messaging for Maestro** | Azure Event Grid MQTT | AWS IoT Core MQTT | TBD (not yet implemented in GCP HCP) |
| **API Management** | Azure Front Door + Istio Ingress Gateway | AWS API Gateway + Application Load Balancer | API Gateway + GKE Ingress (planned) |
| **Bootstrap Mechanism** | Direct deployment via GitHub Actions | ECS-based external bootstrap for ArgoCD | Fleet Config Sync for autonomous cluster bootstrapping + ArgoCD GitOps |
| **Observability Storage** | Azure Data Explorer (Kusto) for long-term metrics/logs | S3 + Thanos for long-term Prometheus metrics | Cloud Storage + Thanos for long-term metrics |
| **Database Strategy** | Mix of Cosmos DB (NoSQL) and PostgreSQL | Mix of DynamoDB (NoSQL) and RDS PostgreSQL | Cloud SQL PostgreSQL + Firestore (NoSQL) |
| **HyperFleet Communication** | Not yet implemented (ARO-specific) | Amazon MQ (RabbitMQ) for Sentinel ↔ Adapter communication | Not yet implemented |
| **Workload Identity** | Azure Managed Identity | IAM Roles for Service Accounts (IRSA) | GKE Workload Identity (keyless authentication) |

---

## Summary

All three platforms follow similar architectural patterns but use cloud-native services specific to their respective cloud providers. The core functionality (Kubernetes, databases, messaging, monitoring, secret management) is equivalent, just implemented with different tools optimized for each cloud.

**Key Takeaways**:
- **ARO-HCP** leverages Azure-native services (AKS, Key Vault, Cosmos DB) with Bicep for IaC
- **ROSA HCP** uses AWS-native services (EKS, S3, DynamoDB) with Terraform and multi-account architecture
- **GCP HCP** utilizes GCP-native services (GKE Autopilot, Secret Manager, Cloud SQL) with Terraform and unique Fleet Config Sync for autonomous bootstrapping
- All three use **ArgoCD** for GitOps and **External Secrets Operator** for secret management
- **Workload Identity** implementations differ but achieve the same goal: secure, keyless authentication

### Service Parity Matrix

| **Capability** | **ARO-HCP (Azure)** | **ROSA HCP (AWS)** | **GCP HCP (GCP)** | **Status** |
|---------------|---------------------|----------------|-------------------|-----------|
| Managed Kubernetes | AKS | EKS | GKE Autopilot/Standard | ✅ Equivalent |
| Object Storage | Blob Storage | S3 | Cloud Storage (GCS) | ✅ Equivalent |
| Key Management | Key Vault | KMS | Cloud KMS | ✅ Equivalent |
| Secrets Management (Infrastructure) | Key Vault | GitHub Secrets + AWS Secrets Manager | Secret Manager + GitHub Secrets | ✅ Equivalent |
| Secrets Management (Application Runtime) | HashiCorp Vault | HashiCorp Vault | External Secrets + Secret Manager | ✅ Equivalent |
| DNS | Azure DNS | Route 53 | Cloud DNS | ✅ Equivalent |
| Load Balancing | Azure LB | ALB | Cloud Load Balancing | ✅ Equivalent |
| Managed Identity | Azure MI | IAM Roles + IRSA | Workload Identity | ✅ Equivalent |
| MQTT Broker | Event Grid MQTT | IoT Core | Pub/Sub (MQTT bridge possible) | ⚠️ Different approach |
| NoSQL Database | Cosmos DB | DynamoDB | Firestore | ✅ Equivalent |
| SQL Database | PostgreSQL Flexible | RDS PostgreSQL | Cloud SQL PostgreSQL | ✅ Equivalent |
| Monitoring | Azure Monitor | CloudWatch | Cloud Monitoring | ✅ Equivalent |
| Log Analytics | Kusto (Data Explorer) | CloudWatch Logs + S3 | Cloud Logging + BigQuery | ⚠️ Different approach |
| Long-term Metrics | Kusto | Thanos + S3 | Thanos + GCS | ✅ Equivalent |
| API Gateway | Front Door + Istio | API Gateway + ALB | API Gateway + GKE Ingress | ⚠️ Different architecture |
| Service Mesh | Istio | Application-level | GKE Service Mesh (Istio) | ⚠️ Varies by platform |
| Message Queue | N/A | Amazon MQ (RabbitMQ) | Pub/Sub | ⚠️ Different approach |
| Policy Engine | Azure RBAC | Cedar/AVP | IAM + Config Connector | ⚠️ Different approach |
| GitOps | ArgoCD (External) | ArgoCD (External) | ArgoCD + Fleet Config Sync | ✅ Equivalent |
| State Management | ARM (built-in) | S3 + DynamoDB | GCS + Cloud Storage | ⚠️ Different approach |

---

---

## Deployment Workflow Comparison

This section compares the CI/CD deployment approaches across all three platforms.

> **📘 Note**: Detailed ROSA HCP workflow examples are provided in [rosa-hcp/workflows/](rosa-hcp/workflows/) directory. For GCP HCP deployment patterns, see the [gcp-hcp-infra](https://github.com/openshift-online/gcp-hcp-infra) repository.

### Workflow Architecture Comparison

| **Aspect** | **ARO-HCP (Azure)** | **ROSA HCP (AWS)** | **GCP HCP (GCP)** |
|------------|---------------------|----------------|-------------------|
| **IaC Tool** | Bicep (Azure native) | Terraform | Terraform |
| **Authentication** | Azure OIDC (Federated Identity) | AWS OIDC (IAM Role with GitHub Provider) | GCP Workload Identity Federation |
| **State Management** | ARM (built-in) | S3 backend + DynamoDB locking | GCS backend (built-in locking) |
| **Deployment Tool** | `az` CLI + custom templatize | `terraform` CLI | `terraform` CLI + `gcloud` |
| **CI/CD Platform** | GitHub Actions | GitHub Actions | GitHub Actions (or Cloud Build) |
| **Deployment Stages** | 1. Infrastructure<br>2. Services | 1. Regional Cluster<br>2. Management Cluster(s)<br>3. Bootstrap (ArgoCD) | 1. Global Infrastructure<br>2. Regional Infrastructure<br>3. Management Clusters<br>4. Fleet Config Sync + ArgoCD |
| **Concurrency** | Workflow-level lock | Terraform state locks | Terraform state locks |
| **Cluster Bootstrap** | Direct deployment | ECS-based external bootstrap | Fleet Config Sync (autonomous) |

---
## Application Secret Management

### Overview

All three platforms use a combination of cloud-native and external secret management solutions for application runtime secrets:

| **Platform** | **Infrastructure Secrets** | **Application Runtime Secrets** | **Integration Method** |
|--------------|---------------------------|--------------------------------|------------------------|
| **ARO-HCP** | Azure Key Vault + GitHub Secrets | Azure Key Vault (native) | Secrets Store CSI Driver |
| **ROSA HCP** | AWS Secrets Manager + GitHub Secrets | HashiCorp Vault (external) | External Secrets Operator or Vault Agent Injector |
| **GCP HCP** | Secret Manager + GitHub Secrets | Secret Manager (native) | External Secrets Operator |

### Platform-Specific Approaches

#### ARO-HCP: Azure Key Vault with CSI Driver

---

ARO-HCP uses **Azure Key Vault** with the **Secrets Store CSI Driver** for application runtime secrets management.

**Integration Pattern**:
- **Secrets Store CSI Driver** - Mounts secrets from Azure Key Vault directly into pods
- **Azure Managed Identity** for authentication
- **SecretProviderClass** custom resources to define secret mappings

#### ROSA HCP: HashiCorp Vault (Proposed)

---

The proposed ROSA HCP pattern uses **HashiCorp Vault** for application runtime secrets management.

📘 **For detailed Vault integration examples (ROSA HCP), see: [vault-integration.md](rosa-hcp/docs/vault-integration.md)**

**Integration Patterns**:
1. **External Secrets Operator (ESO)** - Recommended for Kubernetes-native secret management
2. **Vault Agent Injector** - Direct Vault integration with sidecar injection

**Authentication Methods**:
- **AWS IAM Authentication** - Uses IRSA
- **Kubernetes Authentication** - Uses ServiceAccount tokens

#### GCP HCP: Native Secret Manager Integration

---

GCP HCP uses **Google Cloud Secret Manager** natively integrated via External Secrets Operator.

**Integration Pattern**:
- **External Secrets Operator** with GCP Secret Manager backend
- **Workload Identity** for secure, keyless authentication
- **Secret rotation** via Secret Manager versioning

**Key Differences**:
- ✅ Native GCP integration (no external Vault server)
- ✅ Automatic versioning and rotation
- ✅ Fine-grained IAM policies per secret
- ✅ Lower operational overhead (managed service)

### Secret Types Comparison

| **Secret Type**         | **Storage** | **Use Case** | **Access Method** |
|-------------------------|------------|--------------|-------------------|
| **Infrastructure/CI**   | GitHub Secrets (UI) | Deployment pipeline config, account IDs, IAM role ARNs | GitHub Actions workflows via `${{ secrets.NAME }}` |
| **Application Runtime** | HashiCorp Vault | Database passwords, API keys, certificates | External Secrets Operator or Vault Agent Injector |
| **Application Runtime** | GCP Secret Manager | Database passwords, API keys, certificates | External Secrets Operator |

### Additional Resources

**For HashiCorp Vault**:

The comprehensive Vault integration guide covers:
- Detailed setup for External Secrets Operator (ESO)
- Vault Agent Injector configuration
- Authentication methods (AWS IAM, Azure Managed Identity, and Kubernetes)
- Vault policies and Terraform configuration
- ClusterSecretStore for multi-namespace access
- Best practices and troubleshooting

**📄 See full guide**: [vault-integration.md](rosa-hcp/docs/vault-integration.md)

**For GCP Secret Manager**:

See the [gcp-hcp-infra repository](https://github.com/openshift-online/gcp-hcp-infra) for:
- External Secrets Operator configuration with GCP Secret Manager
- Workload Identity setup for secret access
- Secret Manager integration examples
- Terraform modules for secret provisioning

---

## ROSA HCP-Specific Deployment (Proposed)

> **⚠️ Platform-Specific**: This section provides a high-level overview of the proposed ROSA HCP (AWS) deployment pattern. For detailed instructions, see the [ROSA HCP Deployment Guide](rosa-hcp/docs/deployment-guide.md).

The proposed ROSA HCP deployment pattern uses **GitHub Actions workflows** (following ARO-HCP) for automated infrastructure deployment with:
- **Terraform** for infrastructure as code
- **AWS OIDC** for secure, keyless authentication
- **S3 + DynamoDB** for Terraform state management
- **Multi-account architecture** for isolation and security

### Deployment Workflow Overview (Proposed)

The proposed ROSA HCP deployment follows a sequential pattern:
1. **Regional Cluster** - Deploy base infrastructure (EKS, VPC, RDS, IoT Core, API Gateway)
2. **Management Clusters** - Deploy Hypershift-hosting clusters (multiple per region)
3. **ArgoCD Bootstrap** - Install ArgoCD for GitOps-based application deployment

### Key Resources

- **📘 [Complete Deployment Guide](rosa-hcp/docs/deployment-guide.md)** - Full deployment instructions, prerequisites, and workflows
- **📘 [Vault Integration Guide](rosa-hcp/docs/vault-integration.md)** - HashiCorp Vault setup for ROSA HCP/ARO-HCP
- **📄 [Example Workflows](rosa-hcp/workflows/)** - Complete GitHub Actions workflow files
- **📄 [Example Terraform Variables](rosa-hcp/terraform-examples/tfvars/)** - Sample tfvars files for dev and prod

---

## GCP HCP-Specific Deployment (Proposed)

> **⚠️ Platform-Specific**: This section provides a high-level overview of the proposed GCP HCP deployment pattern. For detailed instructions, see the [GCP HCP Deployment Guide](gcp-hcp/docs/deployment-guide.md).

The proposed GCP HCP deployment uses a **unique approach** that differs from both ARO-HCP and the proposed ROSA HCP pattern, leveraging GCP-native automation:
- **Terraform** for infrastructure as code
- **Fleet Config Sync** for autonomous cluster bootstrapping
- **GCS** for Terraform state with built-in locking
- **Workload Identity** for keyless authentication
- **GCP Secret Manager** for native secret management

### Deployment Workflow Overview (Proposed)

The proposed GCP HCP deployment follows three stages:
1. **Global Infrastructure** - Environment-level control plane (one per environment)
2. **Regional Infrastructure** - Regional GKE clusters (one per sector/region)
3. **Management Clusters** - Hypershift-hosting clusters (multiple per region)

### Fleet Config Sync: GCP HCP's Unique Advantage

Unlike ROSA HCP's GitHub Actions-based bootstrap, GCP HCP uses **Fleet Config Sync** for autonomous cluster bootstrapping. After `terraform apply`, clusters automatically:
- Register in Fleet
- Pull bootstrap manifests from Git
- Deploy ArgoCD and External Secrets Operator
- Self-configure without external CI/CD

### Key Resources

- **📘 [Complete Deployment Guide](gcp-hcp/docs/deployment-guide.md)** - Full deployment instructions, Fleet Config Sync details, and troubleshooting
- **📘 [Secret Manager Integration Guide](gcp-hcp/docs/secret-manager-integration.md)** - GCP Secret Manager with External Secrets Operator
- **📄 [Terraform Examples](gcp-hcp/terraform-examples/)** - Sample configurations for integration and production
- **📄 [Workflows Directory](gcp-hcp/workflows/)** - Explanation of why GCP doesn't use GitHub Actions
- **📄 [GCP HCP Repository](https://github.com/openshift-online/gcp-hcp-infra)** - Full source code and modules

---


## Generated

This comparison was generated on 2026-04-22 by analyzing:
- **ARO-HCP**: [GitHub workflows](https://github.com/Azure/ARO-HCP/blob/main/.github/workflows/aro-hcp-cd.yml) and [Bicep templates](https://github.com/Azure/ARO-HCP/tree/main/dev-infrastructure)
- **ROSA HCP**: [Terraform modules](https://github.com/openshift-online/rosa-regional-platform/tree/main/terraform) and configurations
- **GCP HCP**: [Terraform modules](https://github.com/openshift-online/gcp-hcp-infra/tree/main/terraform/modules) and [deployment guide](https://github.com/openshift-online/gcp-hcp-infra/blob/main/docs/DEPLOYMENT_GUIDE.md)