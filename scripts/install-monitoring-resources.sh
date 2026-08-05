#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"
: "${EXPECTED_CONTEXT:?Set EXPECTED_CONTEXT to the exact target context}"
[[ "${ALLOW_PRODUCTION_APPLY:-false}" == true ]] || {
  printf 'ERROR: set ALLOW_PRODUCTION_APPLY=true after reviewing the target context\n' >&2
  exit 1
}

actual_context=$($KUBECTL_BIN config current-context)
[[ "$actual_context" == "$EXPECTED_CONTEXT" ]] || {
  printf 'ERROR: current context %s does not match EXPECTED_CONTEXT %s\n' \
    "$actual_context" "$EXPECTED_CONTEXT" >&2
  exit 1
}

for resource in podmonitors.monitoring.coreos.com prometheusrules.monitoring.coreos.com; do
  $KUBECTL_BIN api-resources --api-group=monitoring.coreos.com -o name |
    grep -qx "$resource" || {
      printf 'ERROR: required Prometheus Operator resource %s is unavailable\n' "$resource" >&2
      exit 1
    }
done

$KUBECTL_BIN create namespace monitoring --dry-run=client -o yaml |
  $KUBECTL_BIN apply --server-side \
    --field-manager=postgres-k8s-ha-production -f - >/dev/null
$KUBECTL_BIN label namespace monitoring \
  postgres-k8s-ha.io/monitoring=true --overwrite >/dev/null

render=$(mktemp)
cleanup() {
  rm -f "$render"
  rm -rf "$ROOT/monitoring/cloudnative-pg/charts"
}
trap cleanup EXIT

$KUBECTL_BIN kustomize "$ROOT/monitoring/cloudnative-pg" --enable-helm >"$render"
$KUBECTL_BIN apply --server-side --dry-run=server \
  --field-manager=postgres-k8s-ha-production -f "$render" >/dev/null
$KUBECTL_BIN diff --server-side \
  --field-manager=postgres-k8s-ha-production -f "$render" || rc=$?
[[ "${rc:-0}" -le 1 ]] || exit "$rc"
$KUBECTL_BIN apply --server-side \
  --field-manager=postgres-k8s-ha-production -f "$render"
