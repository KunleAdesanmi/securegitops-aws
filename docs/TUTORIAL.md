# SecureGitOps Tutorial

A step-by-step walkthrough for deploying and verifying the SecureGitOps platform. Estimated time: 60-90 minutes for a first run.

## Prerequisites

Install these tools before starting:

| Tool | Version | Install |
|---|---|---|
| AWS CLI | v2 | `brew install awscli` or download from aws.amazon.com |
| Terraform | 1.6+ | `brew install terraform` or use tfenv |
| kubectl | 1.30+ | `brew install kubectl` |
| Helm | 3.x | `brew install helm` |
| Python | 3.10+ | usually preinstalled |
| Git | any recent | `brew install git` |

Configure AWS credentials with sufficient permissions (Administrator for this demo):

```
aws configure
aws sts get-caller-identity
```

## Phase 1 — Bootstrap the Terraform backend

Why this matters: Terraform state contains sensitive resource IDs and must be stored remotely with locking to support team workflows. We use S3 (state) + DynamoDB (lock).

```
cd securegitops-aws
./scripts/bootstrap.sh eu-west-2
```

The script prints the bucket name. Open `terraform/environments/dev-eu-west-2/backend.tf` and `terraform/environments/dev-eu-west-1/backend.tf` — replace `REPLACE_WITH_YOUR_BUCKET` with the printed value in both files.

Verify: `aws s3 ls | grep securegitops-tfstate` should show your bucket.

## Phase 2 — Provision the primary cluster

```
cd terraform/environments/dev-eu-west-2
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

This takes 12-15 minutes. The slow part is EKS control plane creation (~10 min). While you wait, this is what's being built:

- VPC with three AZs, public + private subnets
- Three NAT gateways (one per AZ for HA)
- EKS cluster with KMS-encrypted secrets
- OIDC provider for IRSA
- Managed node group with two t3.medium instances
- VPC flow logs to CloudWatch

Verify:

```
aws eks update-kubeconfig --name securegitops-dev --region eu-west-2
kubectl get nodes
```

Expect 2 nodes in Ready state.

## Phase 3 — Install ArgoCD

```
cd ../../..
./argocd/install/install.sh securegitops-dev eu-west-2
```

The script prints the initial admin password. Save it.

In a separate terminal:

```
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open https://localhost:8080 in a browser, accept the self-signed cert, log in as `admin` with the password from above.

Verify: the ArgoCD UI loads and shows zero applications (we'll add them next).

## Phase 4 — Deploy the demo app via GitOps

Before this works, edit `argocd/apps/root-app.yaml` and `argocd/apps/demo-app.yaml` — replace `YOUR_GH_USER` with your actual GitHub username, then commit and push:

```
git add argocd/apps/
git commit -m "Point ArgoCD at my repo"
git push
```

Apply the root application. ArgoCD will discover the demo-app from there:

```
kubectl apply -f argocd/apps/root-app.yaml
```

Verify: within 1-2 minutes, the ArgoCD UI shows two applications (`root` and `demo-app`) both green and synced. Confirm the workload is running:

```
kubectl -n demo get pods
```

Expect 2 demo-app pods, Running, Ready 1/1.

## Phase 5 — Demonstrate the security gates

This is the screenshot moment for the README. Create a deliberately bad branch:

```
git checkout -b demo/sg-violation
```

Add this resource at the bottom of `terraform/modules/eks/main.tf`:

```
resource "aws_security_group_rule" "bad_demo" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
}
```

Push, open a PR. Within 90 seconds, three CI jobs fail:

- tfsec flags `aws-vpc-no-public-ingress-sgr`
- checkov flags `CKV_AWS_24`
- opa-conftest flags your custom rule with the message "[HIGH] aws_security_group_rule.bad_demo allows SSH from the entire internet"

Screenshot the failed PR Checks tab. This is the highest-value image in your README.

Close the PR, delete the branch:

```
git checkout main
git branch -D demo/sg-violation
git push origin --delete demo/sg-violation
```

## Phase 6 — Capture remaining screenshots

In a fresh browser session with the cluster still running, capture:

1. ArgoCD UI — Applications view showing `root` and `demo-app` synced and healthy. Then click into `demo-app` for the resource tree view.
2. AWS console — EKS — cluster overview showing all five log types enabled, KMS encryption, Active status.
3. AWS console — CloudWatch — log group `/aws/vpc/securegitops-dev/flowlogs` with a recent stream open, showing ACCEPT records.
4. GitHub Actions — workflow run history showing parallel jobs.
5. Terminal — `kubectl -n argocd describe sa argocd-server` with the IRSA annotation visible.

Save them in `docs/screenshots/` with the names referenced in the README.

Privacy check: blur AWS account IDs (12-digit numbers) and any non-RFC1918 IPs before publishing.

## Phase 7 — Tear down

EKS control plane costs around 2 GBP per day even idle. Don't leave it running.

```
cd terraform/environments/dev-eu-west-2
terraform destroy
```

This takes ~10 minutes. The S3 state bucket and DynamoDB table persist (negligible cost) so you can re-deploy quickly later.

## Troubleshooting

`terraform apply` fails on `aws_eks_cluster` with "no available addresses" — your VPC subnets are too small. Check that each /24 subnet is in a different AZ.

ArgoCD app stuck `OutOfSync` — check `kubectl -n argocd logs deploy/argocd-repo-server`. Most often: wrong `repoURL` (still says `YOUR_GH_USER`) or the repo is private and ArgoCD has no credentials.

`kubectl get nodes` returns nothing — the aws-auth ConfigMap may not include your IAM user. Run `aws sts get-caller-identity`, then either deploy from the same identity that ran terraform, or add yourself to `aws-auth` per the EKS docs.

CI fails on `opa-conftest` job for legitimate code — this is expected without AWS credentials in CI. The job is configured to demonstrate the policy; for real enforcement, configure GitHub OIDC to AWS so `terraform plan` can run with real state.
