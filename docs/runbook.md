# SecureGitOps Operational Runbook

## 1. Investigating a failed ArgoCD sync

1. `kubectl -n argocd get applications` — find the application stuck in
   `OutOfSync` or `Degraded`.
2. `argocd app get <name>` (or the UI) → look at the `CONDITIONS` block.
   Common causes: missing namespace, RBAC denial, schema validation error.
3. For schema errors, run `helm template` locally with the same values
   and pipe through `kubeconform -strict`.
4. For drift loops (sync → out-of-sync → sync), check `selfHeal: true`
   isn't fighting a mutating admission webhook.

## 2. Reading VPC flow logs during a connectivity issue

1. `aws logs tail /aws/vpc/securegitops-dev/flowlogs --since 15m`
2. Filter to a specific ENI:
   `--filter-pattern '{ $.interfaceId = "eni-0abc..." }'`
3. `ACCEPT` → traffic was permitted by SG/NACL.
   `REJECT` → blocked. Check SG rules first (stateful, simpler), then NACL.

## 3. Responding to a tfsec finding in a PR

1. Read the rule ID (e.g. `aws-eks-no-public-cluster-access`).
2. Decide: fix or document the exception.
3. To fix: change the resource and push.
4. To document: add a `tfsec:ignore:<rule-id>` inline comment with a
   justification. Exceptions are visible in PR review and tracked in Git.

## 4. Rotating a database secret

```
python3 scripts/secrets-rotate.py \
  --secret-id /securegitops/dev/db-password \
  --new-value "$(openssl rand -base64 24)" \
  --namespace demo --deployment demo-app
```

## 5. Failing over to the DR region

1. Scale up the DR node group: edit `terraform/environments/dev-eu-west-1/main.tf`
   → `node_desired_size = 2` → `terraform apply`.
2. Update Route 53 health check weighting toward `eu-west-1`.
3. Update ArgoCD ApplicationSet (or `destination.server`) to point at the
   DR cluster's API endpoint.
4. Verify: `kubectl --context=dr get pods -A`.
