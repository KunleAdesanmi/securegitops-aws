#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${1:-securegitops-dev}"
REGION="${2:-eu-west-2}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.4/manifests/install.yaml

echo "Waiting for ArgoCD server..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
echo "Port-forward with: kubectl -n argocd port-forward svc/argocd-server 8080:443"
