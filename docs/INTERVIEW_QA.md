# SecureGitOps — Interview Q&A

Use this to prepare for technical screens and panels. Each answer is calibrated to be deliverable in 30-45 seconds out loud.

## Terraform and IaC modularity

**1. Why did you split this into modules?**
Modules are the unit of reuse and the unit of review. A `vpc` module enforces flow logs and locked-down default SGs in one place — every environment that calls it inherits those controls without me having to remember. It also lets me change implementation (say, swap NAT gateways for a NAT instance in dev) without changing every caller.

**2. How do you handle environment-specific differences?**
Each environment is a thin composition layer in `terraform/environments/<env>` that calls modules with environment-specific variables — region, CIDR, instance sizes, node count. The modules themselves are environment-agnostic. This is what makes the multi-region story work: the eu-west-1 DR environment is the same code as eu-west-2 with different inputs and a smaller node group.

**3. What's in your remote state and why?**
S3 with versioning, encryption, and public access blocked, plus DynamoDB for state locking. Versioning protects against accidental corruption — if `terraform apply` ever writes a broken state, I can roll back. Locking prevents two engineers running apply simultaneously, which silently produces inconsistent infrastructure.

**4. How would you handle secrets in Terraform?**
Never in tfvars or state files in plaintext. For this project, sensitive values come from AWS Secrets Manager via data sources at apply time. The state still ends up containing them, which is why the state bucket is encrypted, versioned, and access-restricted. Better still is to provision the secret resource only and have applications fetch values themselves at runtime.

**5. What's the difference between `terraform plan -refresh=false` and a normal plan?**
A normal plan reads current state from AWS and computes a diff against your code. `-refresh=false` skips the AWS read and trusts the local state file. I use it in CI where AWS credentials may not be available — the plan is "speculative" and only shows what the code would do, not what it would do given current reality.

**6. How do you avoid drift?**
Three layers. First, `drift-check.py` runs `terraform plan -detailed-exitcode` across all environments on a schedule and exits 2 if anything changed outside Terraform. Second, IAM policies prevent direct console changes to managed resources. Third, the runbook documents that any emergency manual change must be followed by a Terraform import or code update within 24 hours.

**7. What do you put in a module's `outputs.tf`?**
Only what callers need. The VPC module outputs subnet IDs and the VPC ID — enough for an EKS module to consume them. I don't output internal implementation details like NAT gateway IDs unless something downstream actually needs them. Outputs are part of the module's public API; once published, removing one is a breaking change.

**8. How do you version modules?**
For this project they're local paths because it's a single repo. In a multi-repo setup, modules go in their own repo and consumers reference them by Git tag (`source = "git::...?ref=v1.2.0"`). That decouples module evolution from environment evolution — I can release a new VPC module and roll out adoption gradually.

## AWS networking

**9. Why three AZs and not two?**
EKS recommends a minimum of two, but three gives quorum-friendly behaviour for stateful workloads (etcd, Kafka, anything Raft-based) and means the loss of one AZ leaves you with majority capacity instead of half. The marginal cost is small — three NAT gateways instead of two — and the durability gain is real.

**10. Why one NAT gateway per AZ?**
Two reasons. First, HA: a single NAT in one AZ becomes a single point of failure for outbound traffic from the other two. Second, cross-AZ data transfer charges. If a node in `eu-west-2a` egresses through a NAT in `eu-west-2b`, every byte costs an extra cent. Per-AZ NAT keeps traffic local.

**11. What do VPC flow logs actually capture?**
Source IP, destination IP, ports, protocol, byte and packet counts, action (ACCEPT/REJECT), and the ENI involved. They don't capture packet contents — for that you need traffic mirroring. They're useful for incident investigation ("did this pod talk to S3?"), capacity planning, and detecting anomalous east-west movement, which is often the first sign of compromise.

**12. What's the difference between a security group and a NACL?**
Security groups are stateful and attached to ENIs; NACLs are stateless and attached to subnets. Stateful means an SG that allows inbound on port 443 automatically allows the response — NACLs require explicit ephemeral port rules in both directions. SGs default-deny, NACLs default-allow. I rely on SGs for application-level controls and use NACLs only as a coarse subnet-level safety net.

**13. Why are EKS nodes in private subnets?**
Defence in depth. Even if a misconfigured SG accidentally exposed a node port to the world, there's no public IP — the traffic can't reach it. Public subnets host only NAT gateways and load balancers. Pod-to-internet traffic egresses via NAT; internet-to-pod traffic enters via an ALB or NLB.

**14. How does the EKS control plane reach my private nodes?**
EKS provisions ENIs in the subnets you specify, in your VPC. The control plane talks to nodes via those ENIs — it's not coming from "outside" your VPC. The nodes talk back to the control plane via the cluster endpoint, which can be public, private, or both. In production I'd make it private-only with a VPN or Direct Connect for kubectl.

## EKS, IRSA, and Kubernetes security

**15. Walk me through IRSA end to end.**
The cluster has an OIDC identity provider. When a pod with an annotated ServiceAccount starts, kubelet projects a signed OIDC token into the pod. The AWS SDK in the pod calls `sts:AssumeRoleWithWebIdentity` presenting that token. STS validates the signature against the OIDC provider, checks the role's trust policy permits this specific `namespace:serviceaccount`, and returns temporary credentials. No static keys ever exist.

**16. Why is IRSA better than just giving the node IAM role broad permissions?**
A node role is shared by every pod on that node. If pod A needs S3 read and pod B needs DynamoDB write, the node ends up with both — and a compromised pod A can reach DynamoDB it has no business touching. IRSA scopes IAM to the workload, which is the same boundary Kubernetes uses for everything else.

**17. What does IMDSv2 protect against?**
Server-side request forgery. In IMDSv1, any process on the instance — including a vulnerable web app forced to fetch an attacker URL — could `curl http://169.254.169.254/.../credentials` and exfiltrate the node's IAM credentials. The Capital One breach was exactly this. IMDSv2 requires a session token from a PUT request, which SSRF attacks typically can't forge because they're constrained to GET.

**18. What does the `hop-limit = 2` setting do?**
It controls how many network hops an IMDS response can traverse. Default is 1 — fine for processes on the host, but pods reach IMDS via a virtual interface, which is one hop. Setting it to 2 lets pods reach IMDS while still preventing the credential from leaving the instance via routing tricks.

**19. Why envelope encryption for Kubernetes Secrets?**
By default, Secrets are stored in etcd with a static key managed by AWS. With envelope encryption, each Secret is encrypted with a Data Encryption Key, and the DEK is encrypted with a KMS Customer Master Key. Disclosure of the etcd snapshot alone doesn't reveal Secrets — the attacker also needs KMS access. It also gives you an audit trail: every Secret read is a KMS Decrypt event in CloudTrail.

**20. What's the difference between a SecurityContext at pod level versus container level?**
Pod-level applies to all containers and to volumes (like `fsGroup` for shared volume ownership). Container-level applies to that container only and overrides the pod default. I set `runAsNonRoot` at pod level (a default that should apply everywhere) but `readOnlyRootFilesystem` at container level because some sidecars legitimately need writable roots.

**21. Why drop all capabilities?**
Linux capabilities are the granular pieces of root. `CAP_NET_ADMIN` lets you change network config, `CAP_SYS_PTRACE` lets you debug other processes. Most apps need none of them. Dropping them all and adding back only what's required ("least capability") shrinks the blast radius if the container is compromised — a hijacked process can't load kernel modules or sniff network traffic.

**22. What are some common ways pods get root on the node?**
Privileged containers, `hostPath` mounts to sensitive paths like `/var/run/docker.sock` or `/proc`, host network namespace, and CVEs in the container runtime itself (runc, containerd). Defence is admission control — Pod Security Standards in `restricted` mode, or a policy engine like OPA Gatekeeper or Kyverno that rejects pods with these properties.

## GitOps, ArgoCD, and Helm

**23. What is GitOps actually solving?**
Two problems. First, "what's running in the cluster?" — without GitOps the answer is whatever the last `kubectl apply` did, which nobody remembers. With GitOps, Git is the source of truth and any drift is reverted automatically. Second, audit and rollback — every change is a commit with an author, a diff, and a revert button.

**24. Explain the app-of-apps pattern.**
A single root ArgoCD Application points at a directory of other Application manifests. ArgoCD syncs the root, which creates the children, which sync their own targets. It scales: adding a new app is one YAML file in the apps directory, no `argocd app create` calls or UI clicks. It also makes the entire delivery topology version-controlled.

**25. What does ArgoCD's `selfHeal` actually do?**
If something changes a managed resource outside of Git — someone edits a Deployment via kubectl, a controller mutates an annotation — ArgoCD detects the drift and reapplies the Git-defined state. It's controversial: it can fight with admission webhooks that mutate pods. I enable it for application workloads and disable it for resources that have legitimate runtime mutations.

**26. When would you NOT use ArgoCD?**
For platform-level resources that ArgoCD itself depends on — installing ArgoCD, the AWS Load Balancer Controller, cert-manager. These need to exist before any GitOps loop can run. I install them via Terraform's `helm_release` so the entire stack is reproducible from scratch with `terraform apply`.

**27. Helm vs Kustomize?**
Helm is templating with values; Kustomize is patching of base manifests. Helm wins for distributed software (charts on a registry, many users with many configs). Kustomize wins for first-party manifests where you want clear, declarative diffs between environments. ArgoCD supports both natively. This project uses Helm because the demo-app chart is a typical "third-party-style" deliverable.

**28. How do you handle secrets in Helm charts?**
Never in `values.yaml`. The chart references a Kubernetes Secret by name; the Secret is populated by External Secrets Operator from AWS Secrets Manager, or by sealed-secrets if I want them in Git encrypted. Sealed-secrets is what I'd add as a follow-up to this project.

## Policy-as-code, CI/CD, and DevSecOps

**29. Why use multiple security scanners?**
Each catches different things. tfsec is fast and AWS-aware. Checkov has broader compliance coverage (CIS, NIST, PCI). OPA is for organisation-specific rules tools don't ship out of the box — like "this team's resources must always have a `cost-center` tag". They overlap, but the overlap is a feature: a real bug usually fails multiple scanners, which raises confidence the finding is real.

**30. Walk through what your custom OPA policy does.**
It loads the JSON-formatted Terraform plan and iterates over `resource_changes`. For each change, it checks for known-bad patterns — SSH or RDP open to 0.0.0.0/0, unencrypted EBS volumes, launch templates without IMDSv2. If any matches, it emits a deny message that conftest collects and fails the job on. The policy is plain Rego; anyone on the team can read or extend it.

**31. What's the gap between scanning a plan and scanning a deployed environment?**
A plan tells you what code intends to deploy; it can't tell you about resources that already exist or about runtime state. For full coverage you need both — pre-merge scanning (this project) plus continuous scanning of live AWS via something like Prowler, AWS Security Hub, or Wiz. They complement each other: pre-merge prevents new misconfigurations, continuous scanning catches drift and aged resources.

**32. How would you scale this CI to a large team?**
Three things. Cache `terraform init` output to keep runs under 30 seconds. Use OIDC from GitHub to AWS so plans run with real state — much higher fidelity. And split the workflow per module so a Helm-only PR doesn't trigger Terraform validation. The current setup is fine for one repo with one team; it strains at ten.

**33. What's a "shift-left" security control? Give an example from this repo.**
Shift-left means catching problems earlier — closer to the developer than to production. The OPA policy that rejects an SSH-open-to-the-world rule is shift-left: the developer sees the failure on their PR within 90 seconds, not three days later from a SOC ticket. The cost to fix is also lower: edit a line and re-push versus filing a change request and rolling back live infrastructure.

**34. How do you handle false positives in scanners?**
First, prefer fixing over suppressing — most "false positives" are real findings that just don't apply to my context, which means they'll trip up someone else later. When suppression is genuinely correct, use inline comments (`tfsec:ignore:rule-id`) with a justification, never global ignore lists. The justification is reviewed in PR. Suppressions are auditable and have authors; global ignores rot and accumulate.

## Multi-region, DR, and operations

**35. Active-active vs active-passive — which did you build?**
Active-passive with a pilot light. The DR region runs a minimal cluster (one node) so the control plane is warm and Terraform state is current, but real traffic goes only to primary. On failover I scale up the node group, redirect Route 53, and re-point ArgoCD. Active-active is more expensive and only worth it for genuinely latency-sensitive global traffic — most workloads don't need it.

**36. What's the RPO/RTO for this design?**
RTO target ~30 minutes — time to scale node group, sync ArgoCD, redirect DNS. RPO depends entirely on the data layer: for stateless workloads it's zero, for an RDS database with cross-region read replicas it's minutes, for backup-restore it's hours. The infrastructure tier is the easy part; data replication is where DR projects actually fail.

**37. How would you test DR works?**
Game days. Pick a quarter, schedule a drill, simulate the primary region being unreachable (force-fail the health check), exercise the runbook end to end. Measure actual RTO. Most teams discover their runbooks are subtly wrong on the first drill — undocumented manual steps, stale credentials, missing IAM permissions. The drill is the real value; the runbook is just the artefact.

**38. What's missing from this project that you'd add for production?**
Observability — Prometheus, Grafana, alerts to PagerDuty. External Secrets Operator instead of the Python rotation script. AWS Organizations with separate accounts per environment, governed by SCPs. Karpenter for smarter autoscaling. Backup tooling like Velero. I scoped them out deliberately to keep this repo demonstrative rather than overwhelming, and they're listed in the README's "limitations" section.

**39. Talk me through how you'd investigate ArgoCD reporting an app as "Degraded".**
Start with `argocd app get <name>` for conditions and last sync result. Then `kubectl describe` on the underlying resources — usually a pod CrashLoopBackOff, a missing image pull secret, or a CRD that hasn't been installed. If the manifest looks right, render it locally with `helm template` and run `kubeconform` on the output to catch schema drift between Helm chart version and cluster API version.

**40. A pod can't reach an RDS database. How do you diagnose it?**
Layered: starting at the application and working down. Check the pod logs for the actual error (timeout vs auth vs DNS). `kubectl exec` into the pod, try `nc -zv <rds-endpoint> 5432` — that isolates network from auth. If the connection times out, check the RDS security group allows inbound from the node SG, then check VPC flow logs for REJECT records on that flow. If it's auth, rotate credentials via the secrets-rotate.py script. DNS issues are less common in EKS but show up as "name resolution failures" in pod logs — `kubectl exec` and `nslookup` confirms.
