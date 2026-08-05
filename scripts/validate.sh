#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}

: "${KUBECONFIG:?Set KUBECONFIG to enable server dry-run validation}"

cd "$ROOT"
python3 scripts/check_docs.py
python3 -m py_compile scripts/*.py
bash -n scripts/*.sh scripts/lib/*.sh

tmp=$(mktemp -d)
cleanup() {
  rm -rf "$tmp"
  rm -rf \
    platform/cert-manager/charts \
    platform/cloudnative-pg/charts \
    platform/sealed-secrets/charts \
    platform/longhorn/charts \
    platform/minio/charts
}
trap cleanup EXIT

render() {
  local name=$1
  local directory=$2
  local field_manager=${3:-postgres-k8s-ha}
  "$KUBECTL_BIN" kustomize "$directory" --enable-helm >"$tmp/$name.yaml"
  "$KUBECTL_BIN" apply --server-side --dry-run=server \
    --field-manager="$field_manager" -f "$tmp/$name.yaml" >/dev/null
  printf 'OK: %s render and server dry-run\n' "$name"
}

render cert-manager platform/cert-manager
render cloudnative-pg platform/cloudnative-pg
render barman-cloud platform/barman-cloud
render sealed-secrets platform/sealed-secrets postgres-k8s-ha-production
render longhorn platform/longhorn
render minio platform/minio
render postgres-ha databases/postgres-ha

"$KUBECTL_BIN" kustomize databases/postgres-ha-production \
  >"$tmp/postgres-ha-production.yaml"
python3 scripts/check_production.py \
  --allow-placeholders "$tmp/postgres-ha-production.yaml"
printf 'OK: postgres-ha-production render\n'

python3 scripts/check_render.py "$tmp/longhorn.yaml" "$tmp/minio.yaml"
git diff --check

echo "OK: project validation complete"
