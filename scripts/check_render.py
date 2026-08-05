#!/usr/bin/env python3
"""Check invariants that plain kube schema validation does not cover."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def documents(path: Path) -> list[str]:
    return re.split(r"^---\s*$", path.read_text(encoding="utf-8"), flags=re.MULTILINE)


def top_level_value(document: str, key: str) -> str | None:
    match = re.search(rf"^{re.escape(key)}:\s*(.+?)\s*$", document, re.MULTILINE)
    return match.group(1) if match else None


def metadata_namespace(document: str) -> str | None:
    match = re.search(
        r"^metadata:\s*$.*?^  namespace:\s*(\S+)\s*$",
        document,
        re.MULTILINE | re.DOTALL,
    )
    return match.group(1) if match else None


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: check_render.py <longhorn-render> <minio-render>", file=sys.stderr)
        return 2

    longhorn = Path(sys.argv[1])
    minio = Path(sys.argv[2])
    errors: list[str] = []

    longhorn_jobs = [
        top_level_value(doc, "kind") for doc in documents(longhorn)
        if top_level_value(doc, "kind") == "Job"
    ]
    if longhorn_jobs:
        errors.append("Longhorn render contains Helm hook Jobs")

    minio_text = minio.read_text(encoding="utf-8")
    if "console123" in minio_text:
        errors.append("MinIO render contains insecure upstream default credentials")

    expected_namespaced = {
        "ServiceAccount",
        "ConfigMap",
        "Service",
        "PersistentVolumeClaim",
        "Deployment",
    }
    for doc in documents(minio):
        kind = top_level_value(doc, "kind")
        if kind in expected_namespaced and metadata_namespace(doc) != "minio-lab":
            name_match = re.search(r"^  name:\s*(\S+)", doc, re.MULTILINE)
            name = name_match.group(1) if name_match else "unknown"
            errors.append(f"{kind}/{name} is not explicitly in minio-lab")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print("OK: Kustomize render invariants valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
