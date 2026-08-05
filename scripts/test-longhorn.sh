#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
NAMESPACE=postgres-k8s-ha-test
KEEP_TEST_RESOURCES=${KEEP_TEST_RESOURCES:-false}
MARKER="longhorn-smoke-$(date -u +%Y%m%dT%H%M%SZ)"

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"

cleanup() {
  if [ "$KEEP_TEST_RESOURCES" != true ]; then
    "$KUBECTL_BIN" delete namespace "$NAMESPACE" --wait=true \
      --timeout=5m --ignore-not-found >/dev/null
  fi
}
trap cleanup EXIT

"$KUBECTL_BIN" apply -f "$ROOT/tests/storage/smoke.yaml"
"$KUBECTL_BIN" -n "$NAMESPACE" wait pod/longhorn-smoke \
  --for=condition=Ready --timeout=5m

"$KUBECTL_BIN" -n "$NAMESPACE" exec longhorn-smoke -- \
  sh -c "printf '%s\\n' '$MARKER' > /data/evidence.txt && sync"

"$KUBECTL_BIN" -n "$NAMESPACE" patch pvc longhorn-smoke \
  --type merge -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'

for _ in $(seq 1 60); do
  capacity=$("$KUBECTL_BIN" -n "$NAMESPACE" get pvc longhorn-smoke \
    -o jsonpath='{.status.capacity.storage}')
  [ "$capacity" = 2Gi ] && break
  sleep 2
done
test "${capacity:-}" = 2Gi

"$KUBECTL_BIN" -n "$NAMESPACE" delete pod longhorn-smoke --wait=true
"$KUBECTL_BIN" apply -f "$ROOT/tests/storage/pod.yaml"
"$KUBECTL_BIN" -n "$NAMESPACE" wait pod/longhorn-smoke \
  --for=condition=Ready --timeout=5m

actual=$("$KUBECTL_BIN" -n "$NAMESPACE" exec longhorn-smoke -- \
  cat /data/evidence.txt)
test "$actual" = "$MARKER"

"$KUBECTL_BIN" -n "$NAMESPACE" exec longhorn-smoke -- df -h /data
"$KUBECTL_BIN" -n longhorn-system get volumes.longhorn.io \
  -o custom-columns='NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,SIZE:.spec.size,NODE:.status.currentNodeID'

echo "PASS: write, online expansion 1Gi->2Gi, detach/reattach and persistence"
