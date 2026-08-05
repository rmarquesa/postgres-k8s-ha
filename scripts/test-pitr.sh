#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"

if [[ $("$KUBECTL_BIN" -n postgres-lab get \
  backup.postgresql.cnpg.io/postgres-ha-manual \
  -o jsonpath='{.status.phase}' 2>/dev/null || true) != completed ]]; then
  "$ROOT/scripts/test-backup.sh"
fi

primary=$("$KUBECTL_BIN" -n postgres-lab get pod \
  -l cnpg.io/cluster=postgres-ha,role=primary \
  -o jsonpath='{.items[0].metadata.name}')
probe="pitr-$(date -u +%Y%m%d%H%M%S)"

"$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -X -v ON_ERROR_STOP=1 -d app -c \
  'CREATE TABLE IF NOT EXISTS pitr_probe (probe text NOT NULL, phase text NOT NULL, PRIMARY KEY (probe, phase))'
"$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -X -v ON_ERROR_STOP=1 -d app -c \
  "INSERT INTO pitr_probe VALUES ('$probe', 'before')"

# Use PostgreSQL's clock to avoid relying on workstation/cluster clock alignment.
target_time=$("$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -XAt -d app -c \
  "SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') || '+00'")
sleep 2
"$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -X -v ON_ERROR_STOP=1 -d app -c \
  "INSERT INTO pitr_probe VALUES ('$probe', 'after')"
archived_before=$("$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -XAt -d postgres -c 'SELECT archived_count FROM pg_stat_archiver')
failed_before=$("$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -XAt -d postgres -c 'SELECT failed_count FROM pg_stat_archiver')
"$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -XAt -d postgres -c 'SELECT pg_switch_wal()' >/dev/null

# Wait until the switched WAL is archived without increasing failures.
for _ in $(seq 1 60); do
  archived_after=$("$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
    psql -XAt -d postgres -c 'SELECT archived_count FROM pg_stat_archiver')
  failed_after=$("$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
    psql -XAt -d postgres -c 'SELECT failed_count FROM pg_stat_archiver')
  if (( archived_after > archived_before )) && [[ "$failed_after" == "$failed_before" ]]; then break; fi
  sleep 2
done
(( archived_after > archived_before ))
[[ "$failed_after" == "$failed_before" ]]

"$KUBECTL_BIN" -n postgres-lab delete cluster.postgresql.cnpg.io postgres-ha-restore \
  --ignore-not-found --wait=true

tmp=$(mktemp -d)
cleanup() {
  "$KUBECTL_BIN" -n postgres-lab delete cluster.postgresql.cnpg.io \
    postgres-ha-restore --ignore-not-found --wait=false >/dev/null 2>&1 || true
  "$KUBECTL_BIN" -n postgres-lab delete configmap pitr-input \
    --ignore-not-found >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT
cp -R "$ROOT/tests/pitr/base" "$tmp/base"
cat >"$tmp/target.env" <<EOF
TARGET_TIME=$target_time
EOF
cat >"$tmp/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - base
generatorOptions:
  disableNameSuffixHash: true
configMapGenerator:
  - name: pitr-input
    namespace: postgres-lab
    envs:
      - target.env
replacements:
  - source:
      kind: ConfigMap
      name: pitr-input
      fieldPath: data.TARGET_TIME
    targets:
      - select:
          kind: Cluster
          name: postgres-ha-restore
        fieldPaths:
          - spec.bootstrap.recovery.recoveryTarget.targetTime
EOF

"$KUBECTL_BIN" kustomize "$tmp" >"$tmp/rendered.yaml"
restore_started=$(date +%s)
"$KUBECTL_BIN" apply --server-side --force-conflicts \
  --field-manager=postgres-k8s-ha -f "$tmp/rendered.yaml"
"$KUBECTL_BIN" -n postgres-lab wait cluster.postgresql.cnpg.io/postgres-ha-restore \
  --for=condition=Ready --timeout=15m
restore_seconds=$(( $(date +%s) - restore_started ))

restore_primary=$("$KUBECTL_BIN" -n postgres-lab get pod \
  -l cnpg.io/cluster=postgres-ha-restore,role=primary \
  -o jsonpath='{.items[0].metadata.name}')
before_count=$("$KUBECTL_BIN" -n postgres-lab exec "$restore_primary" -c postgres -- \
  psql -XAt -d app -c \
  "SELECT count(*) FROM pitr_probe WHERE probe='$probe' AND phase='before'")
after_count=$("$KUBECTL_BIN" -n postgres-lab exec "$restore_primary" -c postgres -- \
  psql -XAt -d app -c \
  "SELECT count(*) FROM pitr_probe WHERE probe='$probe' AND phase='after'")

[[ "$before_count" == 1 ]]
[[ "$after_count" == 0 ]]
printf 'PASS: PITR target=%s before=%s after=%s restore_seconds=%s\n' \
  "$target_time" "$before_count" "$after_count" "$restore_seconds"

"$KUBECTL_BIN" -n postgres-lab delete cluster.postgresql.cnpg.io postgres-ha-restore --wait=true
"$KUBECTL_BIN" -n postgres-lab delete configmap pitr-input --ignore-not-found
