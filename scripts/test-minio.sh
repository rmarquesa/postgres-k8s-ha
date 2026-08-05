#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
NAMESPACE=minio-lab

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"

"$KUBECTL_BIN" -n "$NAMESPACE" delete job minio-s3-smoke \
  --ignore-not-found --wait=true
"$KUBECTL_BIN" apply -f "$ROOT/tests/minio/s3-smoke.yaml"

if ! "$KUBECTL_BIN" -n "$NAMESPACE" wait job/minio-s3-smoke \
  --for=condition=Complete --timeout=5m; then
  "$KUBECTL_BIN" -n "$NAMESPACE" logs job/minio-s3-smoke --all-containers=true
  exit 1
fi

"$KUBECTL_BIN" -n "$NAMESPACE" logs job/minio-s3-smoke --all-containers=true
"$KUBECTL_BIN" -n "$NAMESPACE" get pvc,pod,svc
