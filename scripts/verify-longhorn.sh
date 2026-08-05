#!/usr/bin/env bash
set -euo pipefail

KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"

# The driver deployer creates CSI resources asynchronously after Helm reports
# the release ready. Wait for the DaemonSet to exist before checking rollout.
for _ in $(seq 1 60); do
  if "$KUBECTL_BIN" -n longhorn-system get daemonset/longhorn-csi-plugin \
    >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
"$KUBECTL_BIN" -n longhorn-system get daemonset/longhorn-csi-plugin >/dev/null
"$KUBECTL_BIN" -n longhorn-system rollout status \
  daemonset/longhorn-csi-plugin --timeout=5m

for deployment in csi-attacher csi-provisioner csi-resizer csi-snapshotter; do
  "$KUBECTL_BIN" -n longhorn-system rollout status \
    "deployment/$deployment" --timeout=5m
done

"$KUBECTL_BIN" -n longhorn-system rollout status \
  deployment/longhorn-ui --timeout=5m
"$KUBECTL_BIN" -n longhorn-system wait pod \
  -l longhorn.io/component=instance-manager \
  --for=condition=Ready --timeout=5m
"$KUBECTL_BIN" -n longhorn-system wait pod \
  -l longhorn.io/component=engine-image \
  --for=condition=Ready --timeout=5m

workers=$("$KUBECTL_BIN" get nodes \
  -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{.items[*].metadata.name}')

for node in $workers; do
  ready=$("$KUBECTL_BIN" -n longhorn-system get nodes.longhorn.io "$node" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  schedulable=$("$KUBECTL_BIN" -n longhorn-system get nodes.longhorn.io "$node" \
    -o jsonpath='{.status.conditions[?(@.type=="Schedulable")].status}')
  printf '%s ready=%s schedulable=%s\n' "$node" "$ready" "$schedulable"
  test "$ready" = True
  test "$schedulable" = True
 done

"$KUBECTL_BIN" get storageclass longhorn-postgres longhorn-lab
