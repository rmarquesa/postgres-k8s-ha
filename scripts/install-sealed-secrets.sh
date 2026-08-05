#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"
: "${EXPECTED_CONTEXT:?Set EXPECTED_CONTEXT to the exact target context}"

actual_context=$($KUBECTL_BIN config current-context)
if [[ "$actual_context" != "$EXPECTED_CONTEXT" ]]; then
  printf 'ERROR: current context %s does not match EXPECTED_CONTEXT %s\n' \
    "$actual_context" "$EXPECTED_CONTEXT" >&2
  exit 1
fi

rendered=$(mktemp)
cleanup() {
  rm -f "$rendered"
  rm -rf "$ROOT/platform/sealed-secrets/charts"
}
trap cleanup EXIT

$KUBECTL_BIN kustomize "$ROOT/platform/sealed-secrets" --enable-helm >"$rendered"
$KUBECTL_BIN apply --server-side --dry-run=server \
  --field-manager=postgres-k8s-ha-production -f "$rendered" >/dev/null
$KUBECTL_BIN apply --server-side \
  --field-manager=postgres-k8s-ha-production -f "$rendered"

$KUBECTL_BIN wait crd/sealedsecrets.bitnami.com \
  --for=condition=Established --timeout=2m
$KUBECTL_BIN -n kube-system rollout status \
  deployment/sealed-secrets-controller --timeout=5m
