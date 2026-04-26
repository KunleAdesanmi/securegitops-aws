#!/usr/bin/env python3
"""
drift-check.py — Detect Terraform drift across all environments.

Runs `terraform plan` in each environment dir and reports any non-empty diff.
Exit code 2 if drift detected, 0 if clean, 1 on error.

Usage:
    python3 scripts/drift-check.py [--root terraform/environments]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    """Run a command and return the completed process. Never raises."""
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def plan_env(env_dir: Path) -> tuple[str, int]:
    """Generate a plan and count resource changes. Returns (env_name, changes)."""
    print(f"\n=== {env_dir.name} ===", flush=True)

    init = run(["terraform", "init", "-input=false", "-no-color"], env_dir)
    if init.returncode != 0:
        print(f"  init failed:\n{init.stderr}", file=sys.stderr)
        return env_dir.name, -1

    plan = run(
        ["terraform", "plan", "-detailed-exitcode", "-no-color", "-out=drift.tfplan"],
        env_dir,
    )

    # detailed-exitcode contract:
    #   0 = no changes, 1 = error, 2 = changes present
    if plan.returncode == 1:
        print(f"  plan errored:\n{plan.stderr}", file=sys.stderr)
        return env_dir.name, -1

    if plan.returncode == 0:
        print("  ✓ no drift")
        return env_dir.name, 0

    show = run(
        ["terraform", "show", "-json", "drift.tfplan"], env_dir
    )
    if show.returncode != 0:
        print(f"  show failed:\n{show.stderr}", file=sys.stderr)
        return env_dir.name, -1

    data = json.loads(show.stdout)
    changes = [
        rc for rc in data.get("resource_changes", [])
        if rc["change"]["actions"] != ["no-op"]
    ]
    print(f"  ✗ DRIFT — {len(changes)} resources changed:")
    for c in changes:
        actions = ",".join(c["change"]["actions"])
        print(f"      [{actions}] {c['address']}")
    return env_dir.name, len(changes)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default="terraform/environments",
        help="Directory containing per-env subdirs.",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"Not a directory: {root}", file=sys.stderr)
        return 1

    env_dirs = sorted(d for d in root.iterdir() if d.is_dir())
    results = [plan_env(d) for d in env_dirs]

    print("\n=== summary ===")
    drifted = [n for n, c in results if c > 0]
    errored = [n for n, c in results if c < 0]
    for name, count in results:
        status = "ERROR" if count < 0 else ("DRIFT" if count > 0 else "OK")
        print(f"  {name:30s} {status}")

    if errored:
        return 1
    if drifted:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
