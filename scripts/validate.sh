#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}

: "${KUBECONFIG:?Set KUBECONFIG to enable server dry-run validation}"

cd "$ROOT"
python3 scripts/check_docs.py
python3 -m py_compile scripts/check_docs.py scripts/check_render.py
bash -n scripts/*.sh scripts/lib/*.sh

tmp=$(mktemp -d)
cleanup() {
  rm -rf "$tmp"
  rm -rf \
    platform/cert-manager/charts \
    platform/cloudnative-pg/charts \
    platform/longhorn/charts \
    platform/minio/charts
}
trap cleanup EXIT

render() {
  local name=$1
  local directory=$2
  "$KUBECTL_BIN" kustomize "$directory" --enable-helm >"$tmp/$name.yaml"
  "$KUBECTL_BIN" apply --server-side --dry-run=server \
    --field-manager=postgres-k8s-ha -f "$tmp/$name.yaml" >/dev/null
  printf 'OK: %s render and server dry-run\n' "$name"
}

render cert-manager platform/cert-manager
render cloudnative-pg platform/cloudnative-pg
render barman-cloud platform/barman-cloud
render longhorn platform/longhorn
render minio platform/minio
render postgres-ha databases/postgres-ha

python3 scripts/check_render.py "$tmp/longhorn.yaml" "$tmp/minio.yaml"
git diff --check

echo "OK: project validation complete"
