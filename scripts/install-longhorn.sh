#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
. "$ROOT/scripts/lib/kustomize.sh"

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"

"$KUBECTL_BIN" cluster-info >/dev/null

# The control-plane remains tainted and does not receive a default Longhorn disk.
while IFS= read -r node; do
  "$KUBECTL_BIN" label node "$node" \
    node.longhorn.io/create-default-disk=true --overwrite
  echo "labelled Longhorn worker: $node"
done < <(
  "$KUBECTL_BIN" get nodes \
    -l '!node-role.kubernetes.io/control-plane' \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)

kustomize_apply "$ROOT/platform/longhorn"
"$KUBECTL_BIN" -n longhorn-system rollout status daemonset/longhorn-manager --timeout=5m
"$KUBECTL_BIN" -n longhorn-system rollout status deployment/longhorn-driver-deployer --timeout=5m

"$ROOT/scripts/verify-longhorn.sh"
