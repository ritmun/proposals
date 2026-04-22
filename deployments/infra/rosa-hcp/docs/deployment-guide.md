# ROSA HCP - GitHub Actions Deployment Guide (Proposed)

> **Platform**: Red Hat OpenShift Service on AWS (ROSA) Hosted Control Planes
> **Deployment Method**: GitHub Actions workflows with Terraform (Proposed)
> **Based on**: ARO-HCP continuous deployment patterns
> **Status**: Reference implementation proposal

This guide provides comprehensive instructions for how ROSA HCP infrastructure **could be deployed** using GitHub Actions workflows, following the ARO-HCP pattern.

---

## Overview

This proposed ROSA HCP deployment approach uses GitHub Actions for automated infrastructure deployment, leveraging:
- **Terraform** for infrastructure as code
- **AWS OIDC** for secure, keyless authentication
- **S3 + DynamoDB** for Terraform state management
- **Multi-account architecture** for isolation and security

**📄 Reference Implementation Examples**: All workflow files referenced in this guide are available in this directory as examples.

---

## Prerequisites

### 1. AWS Account Setup

For ROSA HCP deployment, you need:
- **Central Account**: Hosts CodePipeline/shared infrastructure (optional for GitHub Actions)
- **Regional Cluster Account(s)**: One per region for Regional Clusters
- **Management Cluster Account(s)**: Multiple per region for Management Clusters
- **AWS Organizations** (recommended): For multi-account management

### 2. GitHub OIDC Setup for AWS

Create an IAM OIDC Identity Provider in each AWS account:

```bash
# Run this in your AWS account(s)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 3. Create GitHub Actions IAM Roles

Create an IAM role in each AWS account with the following trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/rosa-regional-platform:*"
        }
      }
    }
  ]
}
```

**Attach appropriate permissions policies**:
- `PowerUserAccess` (for infrastructure deployment)
- Custom policy for Terraform state access (S3 + DynamoDB)
- Cross-account assume role permissions (for multi-account)

### 4. Required GitHub Secrets (CI/CD Pipeline Configuration)

> **Important**: These secrets are stored in **GitHub's secure UI** (Repository Settings → Secrets and variables → Actions), **NOT in code files**. They are used exclusively for CI/CD pipeline authentication and infrastructure deployment configuration.
>
> For **application runtime secrets** (database passwords, API keys, etc.), ROSA HCP uses **HashiCorp Vault** - see [vault-integration.md](vault-integration.md) for details.

Configure the following secrets in your GitHub repository's Settings UI:

| **Secret Name**                  | **Description**                                | **Example Value**                                  |
|----------------------------------|------------------------------------------------|----------------------------------------------------|
| `AWS_REGION`                     | Primary AWS region                             | `us-east-1`                                        |
| `AWS_ACCOUNT_ID_REGIONAL`        | Regional Cluster AWS account ID                | `123456789012`                                     |
| `AWS_ACCOUNT_ID_MANAGEMENT`      | Management Cluster AWS account ID              | `234567890123`                                     |
| `AWS_ROLE_TO_ASSUME_REGIONAL`    | IAM role ARN for Regional Cluster deployment   | `arn:aws:iam::123456789012:role/GitHubActionsRole` |
| `AWS_ROLE_TO_ASSUME_MANAGEMENT`  | IAM role ARN for Management Cluster deployment | `arn:aws:iam::234567890123:role/GitHubActionsRole` |
| `TERRAFORM_STATE_BUCKET`         | S3 bucket for Terraform state                  | `rosa-platform-terraform-state`                    |
| `TERRAFORM_STATE_DYNAMODB_TABLE` | DynamoDB table for state locking               | `rosa-platform-terraform-locks`                    |

---

## Using the Example Workflows

To use these workflows in your ROSA HCP repository:

1. **Copy the example workflows**:
   ```bash
   cp -r /path/to/this/repo/rosa/workflows/*.yml /path/to/rosa-regional-platform/.github/workflows/
   ```

2. **Configure GitHub Secrets** (see [Required GitHub Secrets](#4-required-github-secrets-cicd-pipeline-configuration) section above)

3. **Set up AWS OIDC** (see [GitHub OIDC Setup](#2-github-oidc-setup-for-aws) section above)

4. **Customize for your environment** (update regions, account IDs, etc.)

5. **Trigger the main workflow** manually or via automated triggers

For additional context, see the [README.md](README.md).

---

## Workflow Details

### Main Workflow: `rosa-hcp-cd.yml`

This is the main orchestrator workflow, similar to ARO-HCP's `aro-hcp-cd.yml`.

**📄 Full workflow**: [rosa-hcp-cd.yml](rosa-hcp-cd.yml)

**Key features**:
- Preflight validation checks
- Environment selection (dev/int/stage/prod)
- Sequential deployment: Regional Cluster → Management Clusters → ArgoCD Bootstrap
- Triggered manually or after container image builds
- Environment-level concurrency control

---

### Regional Cluster Deployment: `regional-cluster-cd.yml`

This reusable workflow deploys the Regional Cluster infrastructure (EKS, VPC, RDS, IoT Core, API Gateway, etc.).

**📄 Full workflow**: [regional-cluster-cd.yml](regional-cluster-cd.yml)

**Key features**:
- Terraform format validation
- S3 backend initialization with state locking
- Plan and apply Terraform changes
- Save outputs as GitHub artifacts
- OIDC authentication with AWS

---

### Management Cluster Deployment: `management-cluster-cd.yml`

This reusable workflow deploys Management Cluster(s) that host HCP workloads.

**📄 Full workflow**: [management-cluster-cd.yml](management-cluster-cd.yml)

**Key features**:
- Matrix strategy for deploying multiple clusters
- Sequential deployment (max-parallel: 1) to avoid conflicts
- Cross-account IAM role assumption
- Kubectl access verification
- Separate state file per cluster

---

### ArgoCD Bootstrap: `bootstrap-argocd.yml`

This workflow bootstraps ArgoCD on the Regional Cluster for GitOps-based deployments.

**📄 Full workflow**: [bootstrap-argocd.yml](bootstrap-argocd.yml)

**Key features**:
- Installs ArgoCD in dedicated namespace
- Waits for all pods to be ready
- Applies ApplicationSet configurations
- Uses kubectl and Helm for deployment

---

## Environment-Specific Variables

Create variable files in `deploy/<environment>/`:

**Example configuration files**:
- 📄 [Dev Environment](../terraform-examples/tfvars/dev-regional-cluster.tfvars) - Development configuration with cost-optimized settings
- 📄 [Production Environment](../terraform-examples/tfvars/prod-regional-cluster.tfvars) - Production configuration with high availability

These example files include configuration for:
- Network and compute resources
- Database settings (RDS PostgreSQL)
- Message queue configuration (Amazon MQ)
- Authorization (DynamoDB)
- DNS and optional features

---

## Directory Structure for ROSA HCP Workflows

```
rosa-regional-platform/
├── .github/
│   └── workflows/
│       ├── rosa-hcp-cd.yml                    # Main orchestrator
│       ├── regional-cluster-cd.yml            # Regional cluster deployment
│       ├── management-cluster-cd.yml          # Management cluster deployment
│       ├── bootstrap-argocd.yml               # ArgoCD bootstrap
│       └── terraform-plan-pr.yml              # PR validation (optional)
├── deploy/
│   ├── dev/
│   │   ├── regional-cluster.tfvars            # Environment-specific vars
│   │   └── management-cluster.tfvars
│   ├── int/
│   ├── stage/
│   └── prod/
├── terraform/
│   └── config/
│       ├── regional-cluster/
│       │   ├── main.tf
│       │   ├── backend.tf
│       │   └── variables.tf
│       └── management-cluster/
│           ├── main.tf
│           ├── backend.tf
│           └── variables.tf
└── examples/
    └── tfvars/
        ├── dev-regional-cluster.tfvars        # Example dev config
        └── prod-regional-cluster.tfvars       # Example prod config
```

**Reference Documentation** (in this repository):
- 📘 [vault-integration.md](vault-integration.md) - HashiCorp Vault integration guide
- 📄 [GitHub Actions Workflows](../workflows/) - Example GitHub Actions workflows

---

## Key Differences from ARO-HCP Workflow

| **Aspect** | **ARO-HCP** | **ROSA** |
|------------|-------------|----------|
| **State Management** | ARM automatically handles | Must configure S3 backend explicitly |
| **Multi-Account** | Single subscription | Cross-account role assumption required |
| **Validation** | `az deployment what-if` | `terraform plan` |
| **Deployment** | `az deployment create` | `terraform apply` |
| **Tool Installation** | Built into ubuntu-latest | Requires `setup-terraform` action |
| **Bicep/Terraform** | Bicep compilation built-in | Terraform init downloads providers |
| **Bootstrap** | Direct deployment | ECS tasks + kubectl (or GitHub Actions) |

---

## Advanced Features

### Terraform Plan on Pull Requests

**📄 Full workflow**: [terraform-plan-pr.yml](terraform-plan-pr.yml)

This workflow automatically runs Terraform plan on pull requests and posts the results as a comment. It helps reviewers understand infrastructure changes before merging.

**Features**:
- Triggers on changes to `terraform/**`, `deploy/**`, or workflow files
- Runs Terraform plan against dev environment
- Posts formatted plan output as PR comment
- Prevents infrastructure surprises before deployment

---

## Security Best Practices

1. **Use OIDC instead of long-lived credentials**
2. **Scope IAM roles to minimum required permissions**
3. **Enable Terraform state encryption** (S3 + KMS)
4. **Use DynamoDB locking** to prevent concurrent modifications
5. **Protect main branch** - require PR reviews before merge
6. **Use GitHub Environments** with approval gates for prod
7. **Rotate IAM roles regularly**
8. **Enable AWS CloudTrail** for audit logging
9. **Use separate AWS accounts** for different environments
10. **Store sensitive values in GitHub Secrets**, never in code

---

## Troubleshooting

### Common Issues

| **Issue** | **Cause** | **Solution** |
|-----------|-----------|--------------|
| `Error: OIDC token validation failed` | Incorrect trust policy | Verify IAM role trust policy matches repository |
| `Error: Backend initialization failed` | S3 bucket/DynamoDB not found | Create backend resources first |
| `Error: State locked` | Previous run didn't complete | Manually unlock via DynamoDB console |
| `Error: Provider registry unreachable` | Network/firewall issue | Check GitHub Actions network connectivity |
| `Error: Insufficient permissions` | IAM role lacks permissions | Attach required policies to IAM role |

---

## Additional Resources

- **[Infrastructure Comparison](../../infrastructure-comparison.md)** - ARO-HCP vs ROSA HCP vs GCP HCP comparison
- **[Vault Integration Guide](vault-integration.md)** - HashiCorp Vault setup for ROSA HCP/ARO-HCP
- **[ROSA HCP Repository](https://github.com/openshift-online/rosa-regional-platform)** - Official ROSA HCP repository
- **[ARO-HCP Repo](https://github.com/Azure/ARO-HCP)** - ARO-HCP reference implementation
