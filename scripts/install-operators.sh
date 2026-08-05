#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
. "$ROOT/scripts/lib/kustomize.sh"

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"

kustomize_apply "$ROOT/platform/cert-manager"
for deployment in cert-manager cert-manager-webhook cert-manager-cainjector; do
  "$KUBECTL_BIN" -n cert-manager rollout status \
    "deployment/$deployment" --timeout=5m
done
"$KUBECTL_BIN" wait crd/certificates.cert-manager.io \
  --for=condition=Established --timeout=2m

kustomize_apply "$ROOT/platform/cloudnative-pg"
"$KUBECTL_BIN" -n cnpg-system rollout status \
  deployment/cnpg-cloudnative-pg --timeout=5m

kustomize_apply "$ROOT/platform/barman-cloud"
"$KUBECTL_BIN" wait crd/objectstores.barmancloud.cnpg.io \
  --for=condition=Established --timeout=2m
"$KUBECTL_BIN" -n cnpg-system rollout status \
  deployment/barman-cloud --timeout=5m

"$KUBECTL_BIN" -n cnpg-system get deployment \
  cnpg-cloudnative-pg barman-cloud \
  -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image'
