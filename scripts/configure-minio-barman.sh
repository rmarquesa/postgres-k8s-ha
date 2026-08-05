#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
. "$ROOT/scripts/lib/kustomize.sh"

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"
command -v openssl >/dev/null

if ! "$KUBECTL_BIN" -n minio-lab get secret barman-s3-credentials \
  >/dev/null 2>&1; then
  access_key="barman-$(openssl rand -hex 6)"
  secret_key=$(openssl rand -base64 32 | tr -d '\n')
  "$KUBECTL_BIN" -n minio-lab create secret generic barman-s3-credentials \
    --from-literal=ACCESS_KEY_ID="$access_key" \
    --from-literal=ACCESS_SECRET_KEY="$secret_key"
  unset access_key secret_key
fi

"$KUBECTL_BIN" -n minio-lab delete job minio-configure-barman \
  --ignore-not-found --wait=true
kustomize_apply "$ROOT/platform/minio/barman"

if ! "$KUBECTL_BIN" -n minio-lab wait job/minio-configure-barman \
  --for=condition=Complete --timeout=5m; then
  "$KUBECTL_BIN" -n minio-lab logs job/minio-configure-barman \
    --all-containers=true
  exit 1
fi
"$KUBECTL_BIN" -n minio-lab logs job/minio-configure-barman \
  --all-containers=true

kustomize_apply "$ROOT/databases/postgres-ha/bootstrap"
access_key=$("$KUBECTL_BIN" -n minio-lab get secret barman-s3-credentials \
  -o jsonpath='{.data.ACCESS_KEY_ID}' | base64 --decode)
secret_key=$("$KUBECTL_BIN" -n minio-lab get secret barman-s3-credentials \
  -o jsonpath='{.data.ACCESS_SECRET_KEY}' | base64 --decode)
"$KUBECTL_BIN" -n postgres-lab create secret generic s3-backup-credentials \
  --from-literal=ACCESS_KEY_ID="$access_key" \
  --from-literal=ACCESS_SECRET_KEY="$secret_key" \
  --dry-run=client -o yaml | "$KUBECTL_BIN" apply -f -
unset access_key secret_key

echo "PASS: Barman credentials materialized in postgres-lab without output"
