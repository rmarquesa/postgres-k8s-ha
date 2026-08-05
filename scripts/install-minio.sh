#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
NAMESPACE=minio-lab
. "$ROOT/scripts/lib/kustomize.sh"

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"
command -v openssl >/dev/null

kustomize_apply "$ROOT/platform/minio/bootstrap"

if ! "$KUBECTL_BIN" -n "$NAMESPACE" get secret minio-root-credentials \
  >/dev/null 2>&1; then
  root_user=postgres-backup
  root_password=$(openssl rand -base64 32 | tr -d '\n')
  "$KUBECTL_BIN" -n "$NAMESPACE" create secret generic minio-root-credentials \
    --from-literal=rootUser="$root_user" \
    --from-literal=rootPassword="$root_password"
  unset root_password
fi

kustomize_apply "$ROOT/platform/minio"
"$KUBECTL_BIN" -n "$NAMESPACE" rollout status deployment/minio --timeout=5m
"$ROOT/scripts/configure-minio-barman.sh"
"$ROOT/scripts/test-minio.sh"
