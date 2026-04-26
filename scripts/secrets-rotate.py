#!/usr/bin/env python3
"""
secrets-rotate.py — Rotate a value in AWS Secrets Manager and trigger a
rolling restart of the EKS deployments that consume it.

Usage:
    python3 scripts/secrets-rotate.py \
        --secret-id /securegitops/dev/db-password \
        --new-value "$(openssl rand -base64 24)" \
        --namespace default \
        --deployment demo-app
"""
from __future__ import annotations

import argparse
import datetime as dt
import sys

import boto3  # type: ignore
from botocore.exceptions import ClientError  # type: ignore
from kubernetes import client, config  # type: ignore


def rotate_secret(secret_id: str, new_value: str, region: str) -> str:
    """Put a new version of the secret. Returns the new version's ARN."""
    sm = boto3.client("secretsmanager", region_name=region)
    try:
        resp = sm.put_secret_value(SecretId=secret_id, SecretString=new_value)
    except ClientError as e:
        print(f"Failed to rotate {secret_id}: {e}", file=sys.stderr)
        raise
    print(f"Rotated {secret_id} → version {resp['VersionId']}")
    return resp["ARN"]


def restart_deployment(namespace: str, deployment: str) -> None:
    """Patch the deployment's pod template to force a rollout.
    This is the same mechanism `kubectl rollout restart` uses."""
    try:
        config.load_kube_config()
    except Exception:
        config.load_incluster_config()

    apps = client.AppsV1Api()
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    body = {
        "spec": {
            "template": {
                "metadata": {
                    "annotations": {
                        "kubectl.kubernetes.io/restartedAt": now,
                    }
                }
            }
        }
    }
    apps.patch_namespaced_deployment(
        name=deployment, namespace=namespace, body=body
    )
    print(f"Triggered rollout: {namespace}/{deployment}")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--secret-id", required=True)
    p.add_argument("--new-value", required=True)
    p.add_argument("--region", default="eu-west-2")
    p.add_argument("--namespace", required=True)
    p.add_argument("--deployment", required=True)
    p.add_argument(
        "--skip-restart",
        action="store_true",
        help="Rotate the secret but do not restart deployments.",
    )
    args = p.parse_args()

    rotate_secret(args.secret_id, args.new_value, args.region)
    if not args.skip_restart:
        restart_deployment(args.namespace, args.deployment)
    return 0


if __name__ == "__main__":
    sys.exit(main())
