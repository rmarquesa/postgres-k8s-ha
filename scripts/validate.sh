#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}

: "${KUBECONFIG:?Set KUBECONFIG to enable server dry-run validation}"

cd "$ROOT"
python3 scripts/check_docs.py
python3 scripts/check_site.py
python3 -m py_compile scripts/*.py
bash -n scripts/*.sh scripts/lib/*.sh

tmp=$(mktemp -d)
cleanup() {
  rm -rf "$tmp"
  rm -rf \
    platform/cert-manager/charts \
    platform/cloudnative-pg/charts \
    platform/sealed-secrets/charts \
    monitoring/cloudnative-pg/charts \
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

"$KUBECTL_BIN" kustomize monitoring/cloudnative-pg --enable-helm \
  >"$tmp/cloudnative-pg-monitoring.yaml"
python3 scripts/extract_prometheus_rules.py \
  monitoring/cloudnative-pg/alerts.yaml "$tmp/prometheus-rules.yaml"
if command -v promtool >/dev/null 2>&1; then
  promtool check rules "$tmp/prometheus-rules.yaml" >/dev/null
elif command -v docker >/dev/null 2>&1; then
  docker run --rm --entrypoint=promtool \
    -v "$tmp/prometheus-rules.yaml:/rules.yaml:ro" \
    prom/prometheus:v3.5.0 check rules /rules.yaml >/dev/null
else
  printf 'WARN: promtool rule validation skipped (promtool/docker unavailable)\n'
fi
printf 'OK: CloudNativePG monitoring render and rules\n'

python3 scripts/check_render.py "$tmp/longhorn.yaml" "$tmp/minio.yaml"
git diff --check

echo "OK: project validation complete"
