#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
. "$ROOT/scripts/lib/kustomize.sh"

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"

"$ROOT/scripts/configure-minio-barman.sh"
kustomize_apply "$ROOT/databases/postgres-ha"

"$KUBECTL_BIN" -n postgres-lab wait cluster/postgres-ha \
  --for=condition=Ready --timeout=15m

primary=$("$KUBECTL_BIN" -n postgres-lab get pod \
  -l cnpg.io/cluster=postgres-ha,role=primary \
  -o jsonpath='{.items[0].metadata.name}')

"$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -XAt -d app -c 'SHOW synchronous_standby_names'
"$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -XAt -d app -c \
  "SELECT application_name || ':' || sync_state FROM pg_stat_replication ORDER BY application_name"

"$KUBECTL_BIN" -n postgres-lab get cluster,pod,pvc -o wide
