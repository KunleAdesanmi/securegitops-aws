"""Unit tests for secrets-rotate.py using moto + unittest.mock."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import boto3  # type: ignore
import pytest  # type: ignore
from moto import mock_aws  # type: ignore


def load_module():
    """Load secrets-rotate.py as a module despite the hyphenated filename."""
    path = Path(__file__).parent / "secrets-rotate.py"
    spec = importlib.util.spec_from_file_location("secrets_rotate", path)
    module = importlib.util.module_from_spec(spec)  # type: ignore
    sys.modules["secrets_rotate"] = module
    spec.loader.exec_module(module)  # type: ignore
    return module


@mock_aws
def test_rotate_secret_creates_new_version():
    sm = boto3.client("secretsmanager", region_name="eu-west-2")
    sm.create_secret(Name="/test/secret", SecretString="initial")

    module = load_module()
    arn = module.rotate_secret("/test/secret", "rotated", "eu-west-2")

    assert arn
    current = sm.get_secret_value(SecretId="/test/secret")
    assert current["SecretString"] == "rotated"


def test_restart_deployment_patches_annotation():
    module = load_module()
    fake_apps = MagicMock()
    with patch.object(module.client, "AppsV1Api", return_value=fake_apps), \
         patch.object(module.config, "load_kube_config"):
        module.restart_deployment("default", "demo-app")

    fake_apps.patch_namespaced_deployment.assert_called_once()
    kwargs = fake_apps.patch_namespaced_deployment.call_args.kwargs
    annotations = kwargs["body"]["spec"]["template"]["metadata"]["annotations"]
    assert "kubectl.kubernetes.io/restartedAt" in annotations
