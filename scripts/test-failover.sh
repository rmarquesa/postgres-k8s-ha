#!/usr/bin/env bash
set -euo pipefail

KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"
[[ ${ALLOW_DESTRUCTIVE_TESTS:-false} == true ]] || {
  echo "Set ALLOW_DESTRUCTIVE_TESTS=true to delete the current primary Pod" >&2
  exit 2
}

namespace=postgres-lab
cluster=postgres-ha
old_primary=$("$KUBECTL_BIN" -n "$namespace" get pod \
  -l cnpg.io/cluster="$cluster",role=primary \
  -o jsonpath='{.items[0].metadata.name}')
old_node=$("$KUBECTL_BIN" -n "$namespace" get pod "$old_primary" \
  -o jsonpath='{.spec.nodeName}')
probe="failover-$(date -u +%Y%m%d%H%M%S)"

"$KUBECTL_BIN" -n "$namespace" exec "$old_primary" -c postgres -- \
  psql -X -v ON_ERROR_STOP=1 -d app -c \
  'CREATE TABLE IF NOT EXISTS failover_probe (probe text PRIMARY KEY)'
"$KUBECTL_BIN" -n "$namespace" exec "$old_primary" -c postgres -- \
  psql -X -v ON_ERROR_STOP=1 -d app -c \
  "INSERT INTO failover_probe VALUES ('$probe')"

started=$(date +%s)
"$KUBECTL_BIN" -n "$namespace" delete pod "$old_primary" --wait=false
new_primary=""
for _ in $(seq 1 120); do
  new_primary=$("$KUBECTL_BIN" -n "$namespace" get pod \
    -l cnpg.io/cluster="$cluster",role=primary \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$new_primary" && "$new_primary" != "$old_primary" ]] && \
    "$KUBECTL_BIN" -n "$namespace" get pod "$new_primary" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q True; then
    break
  fi
  sleep 1
done
[[ -n "$new_primary" && "$new_primary" != "$old_primary" ]]
elapsed=$(( $(date +%s) - started ))

value=$("$KUBECTL_BIN" -n "$namespace" exec "$new_primary" -c postgres -- \
  psql -XAt -d app -c \
  "SELECT count(*) FROM failover_probe WHERE probe='$probe'")
[[ "$value" == 1 ]]

"$KUBECTL_BIN" -n "$namespace" wait cluster.postgresql.cnpg.io/"$cluster" \
  --for=condition=Ready --timeout=10m
new_node=$("$KUBECTL_BIN" -n "$namespace" get pod "$new_primary" \
  -o jsonpath='{.spec.nodeName}')

printf 'PASS: failover old=%s/%s new=%s/%s rto_seconds=%s durable_row=%s\n' \
  "$old_primary" "$old_node" "$new_primary" "$new_node" "$elapsed" "$value"
"$KUBECTL_BIN" -n "$namespace" get pod \
  -l cnpg.io/cluster="$cluster" -o wide
