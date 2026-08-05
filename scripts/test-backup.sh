#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
. "$ROOT/scripts/lib/kustomize.sh"

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"

"$KUBECTL_BIN" -n postgres-lab delete backup.postgresql.cnpg.io postgres-ha-manual \
  --ignore-not-found --wait=true
kustomize_apply "$ROOT/tests/backup/manual"

if ! "$KUBECTL_BIN" -n postgres-lab wait backup.postgresql.cnpg.io/postgres-ha-manual \
  --for=jsonpath='{.status.phase}'=completed --timeout=15m; then
  "$KUBECTL_BIN" -n postgres-lab get backup.postgresql.cnpg.io postgres-ha-manual -o yaml
  exit 1
fi

"$KUBECTL_BIN" -n postgres-lab delete job verify-barman-objects \
  --ignore-not-found --wait=true
kustomize_apply "$ROOT/tests/backup/verify"
if ! "$KUBECTL_BIN" -n postgres-lab wait job/verify-barman-objects \
  --for=condition=Complete --timeout=5m; then
  "$KUBECTL_BIN" -n postgres-lab logs job/verify-barman-objects --all-containers=true
  exit 1
fi
"$KUBECTL_BIN" -n postgres-lab logs job/verify-barman-objects --all-containers=true
"$KUBECTL_BIN" -n postgres-lab get backup.postgresql.cnpg.io postgres-ha-manual \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,STARTED:.status.startedAt,STOPPED:.status.stoppedAt,INSTANCE:.status.instanceID.podName'
