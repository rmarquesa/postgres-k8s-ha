#!/usr/bin/env python3
"""Validate the rendered production profile before any apply."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("render", type=Path)
    parser.add_argument("--allow-placeholders", action="store_true")
    args = parser.parse_args()

    text = args.render.read_text(encoding="utf-8")
    required = (
        "namespace: postgres-prod",
        "storageClass: postgres-production",
        "primaryUpdateStrategy: supervised",
        "enablePDB: true",
        "backupOwnerReference: self",
        "immediate: true",
        "hostnossl all all all reject",
        "kind: DatabaseRole",
        "kind: NetworkPolicy",
        "name: app-runtime-credentials",
        "name: app-migrator-credentials",
        "name: s3-backup-credentials",
    )
    errors = [f"missing invariant: {item}" for item in required if item not in text]

    forbidden = (
        "namespace: minio-lab",
        "storageClass: longhorn-postgres",
        "endpointURL: http://",
        "superuser: true",
    )
    errors.extend(f"forbidden production value: {item}" for item in forbidden if item in text)

    if not args.allow_placeholders:
        placeholders = ("example.invalid", "replace-with-production-bucket")
        errors.extend(f"unresolved production placeholder: {item}" for item in placeholders if item in text)

    if text.count("kind: DatabaseRole") != 3:
        errors.append("production render must contain exactly three DatabaseRole resources")
    if text.count("kind: NetworkPolicy") < 2:
        errors.append("production render must contain ingress isolation policies")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print("OK: production profile invariants valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
