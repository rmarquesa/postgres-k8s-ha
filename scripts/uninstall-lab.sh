#!/usr/bin/env bash
set -euo pipefail

KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
POSTGRES_NAMESPACE=postgres-lab
MINIO_NAMESPACE=minio-lab
TEST_NAMESPACE=postgres-k8s-ha-test
CLUSTER_NAME=postgres-ha
EXECUTE=false
DELETE_RETAINED_VOLUMES=false

usage() {
  cat <<'EOF'
Usage: uninstall-lab.sh [--execute] [--delete-retained-volumes]

Safely removes only the postgres-k8s-ha lab workloads. Without --execute the
script prints the plan and performs read-only preflight checks.

Required environment:
  KUBECONFIG        Target cluster configuration
  EXPECTED_CONTEXT  Exact kubectl context allowed for the teardown

Options:
  --execute                  Perform the teardown
  --delete-retained-volumes  Permanently delete postgres-lab Retain PVs and
                             their detached Longhorn volumes
  -h, --help                 Show this help

The script does not remove Longhorn, CloudNativePG, Barman, cert-manager,
Sealed Secrets, monitoring resources, CRDs, or any production namespace.
EOF
}

while (($#)); do
  case "$1" in
    --execute) EXECUTE=true ;;
    --delete-retained-volumes) DELETE_RETAINED_VOLUMES=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"
: "${EXPECTED_CONTEXT:?Set EXPECTED_CONTEXT to the exact lab context}"

actual_context=$($KUBECTL_BIN config current-context)
[[ "$actual_context" == "$EXPECTED_CONTEXT" ]] || {
  printf 'ERROR: current context %s does not match EXPECTED_CONTEXT %s\n' \
    "$actual_context" "$EXPECTED_CONTEXT" >&2
  exit 1
}

if $KUBECTL_BIN -n "$POSTGRES_NAMESPACE" get cluster "$CLUSTER_NAME" \
  >/dev/null 2>&1; then
  storage_class=$($KUBECTL_BIN -n "$POSTGRES_NAMESPACE" get cluster \
    "$CLUSTER_NAME" -o jsonpath='{.spec.storage.storageClass}')
  [[ "$storage_class" == longhorn-postgres ]] || {
    printf 'ERROR: %s/%s uses unexpected StorageClass %s; refusing lab teardown\n' \
      "$POSTGRES_NAMESPACE" "$CLUSTER_NAME" "$storage_class" >&2
    exit 1
  }
fi

volumes=$(mktemp)
trap 'rm -f "$volumes"' EXIT
$KUBECTL_BIN get pv -o jsonpath="{range .items[?(@.spec.claimRef.namespace=='$POSTGRES_NAMESPACE')]}{.metadata.name}{'|'}{.spec.csi.volumeHandle}{'\n'}{end}" >"$volumes"

printf 'Context: %s\n' "$actual_context"
printf 'Mode: %s\n' "$($EXECUTE && printf EXECUTE || printf 'PLAN ONLY')"
printf 'Lab resources:\n'
printf '  - CloudNativePG Cluster %s/%s\n' "$POSTGRES_NAMESPACE" "$CLUSTER_NAME"
printf '  - namespaces %s, %s and %s\n' \
  "$POSTGRES_NAMESPACE" "$MINIO_NAMESPACE" "$TEST_NAMESPACE"
if [[ -s "$volumes" ]]; then
  printf 'Retained PostgreSQL volumes:\n'
  while IFS='|' read -r pv volume; do
    printf '  - PV %s (Longhorn volume %s): %s\n' \
      "$pv" "$volume" \
      "$($DELETE_RETAINED_VOLUMES && printf DELETE || printf PRESERVE)"
  done <"$volumes"
else
  printf 'Retained PostgreSQL volumes: none found\n'
fi

if ! $EXECUTE; then
  printf '\nPlan only; no resources were deleted. Add --execute to run it.\n'
  exit 0
fi

printf '\nDeleting lab database resources...\n'
$KUBECTL_BIN -n "$POSTGRES_NAMESPACE" delete cluster "$CLUSTER_NAME" \
  --ignore-not-found --wait=true --timeout=15m
$KUBECTL_BIN delete namespace "$POSTGRES_NAMESPACE" "$MINIO_NAMESPACE" \
  "$TEST_NAMESPACE" --ignore-not-found --wait=true --timeout=15m

if $DELETE_RETAINED_VOLUMES; then
  while IFS='|' read -r pv volume; do
    [[ -n "$pv" ]] || continue
    if [[ -n "$volume" ]] && $KUBECTL_BIN -n longhorn-system get \
      volumes.longhorn.io "$volume" >/dev/null 2>&1; then
      state=$($KUBECTL_BIN -n longhorn-system get volumes.longhorn.io \
        "$volume" -o jsonpath='{.status.state}')
      [[ "$state" == detached ]] || {
        printf 'ERROR: Longhorn volume %s is %s, not detached; leaving it and PV %s intact\n' \
          "$volume" "$state" "$pv" >&2
        exit 1
      }
      $KUBECTL_BIN -n longhorn-system delete volumes.longhorn.io "$volume" \
        --wait=true --timeout=5m
    fi
    $KUBECTL_BIN delete pv "$pv" --ignore-not-found --wait=true --timeout=5m
  done <"$volumes"
fi

printf 'Lab teardown complete. Shared platform components were preserved.\n'
