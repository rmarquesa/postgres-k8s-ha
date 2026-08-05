#!/usr/bin/env bash
set -euo pipefail

KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
KUBESEAL_BIN=${KUBESEAL_BIN:-kubeseal}
SECRET_NAMESPACE=${SECRET_NAMESPACE:-postgres-prod}

: "${KUBECONFIG:?Set KUBECONFIG to the target cluster configuration}"
: "${EXPECTED_CONTEXT:?Set EXPECTED_CONTEXT to the exact target context}"
: "${SECRET_KIND:?Set SECRET_KIND to s3, app-migrator, or app-runtime}"
: "${OUTPUT:?Set OUTPUT to the destination .sealed.yaml path}"

actual_context=$($KUBECTL_BIN config current-context)
if [[ "$actual_context" != "$EXPECTED_CONTEXT" ]]; then
  printf 'ERROR: current context %s does not match EXPECTED_CONTEXT %s\n' \
    "$actual_context" "$EXPECTED_CONTEXT" >&2
  exit 1
fi

cert=$(mktemp)
sealed=$(mktemp)
cleanup() {
  rm -f "$cert"
  [[ -z "$sealed" ]] || rm -f "$sealed"
}
trap cleanup EXIT

$KUBESEAL_BIN \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --fetch-cert >"$cert"

case "$SECRET_KIND" in
  s3)
    : "${ACCESS_KEY_ID:?Set ACCESS_KEY_ID}"
    : "${ACCESS_SECRET_KEY:?Set ACCESS_SECRET_KEY}"
    secret_name=s3-backup-credentials
    printf 'ACCESS_KEY_ID=%s\nACCESS_SECRET_KEY=%s\n' \
      "$ACCESS_KEY_ID" "$ACCESS_SECRET_KEY" |
      $KUBECTL_BIN create secret generic "$secret_name" \
        --namespace "$SECRET_NAMESPACE" \
        --from-env-file=/dev/stdin --dry-run=client -o json |
      $KUBESEAL_BIN --format yaml --scope strict --cert "$cert" \
        >"$sealed"
    ;;
  app-migrator|app-runtime)
    : "${DB_PASSWORD:?Set DB_PASSWORD}"
    if [[ "$SECRET_KIND" == app-migrator ]]; then
      secret_name=app-migrator-credentials
      username=app_migrator
    else
      secret_name=app-runtime-credentials
      username=app_runtime
    fi
    printf 'username=%s\npassword=%s\n' "$username" "$DB_PASSWORD" |
      $KUBECTL_BIN create secret generic "$secret_name" \
        --namespace "$SECRET_NAMESPACE" \
        --type kubernetes.io/basic-auth \
        --from-env-file=/dev/stdin --dry-run=client -o json |
      $KUBESEAL_BIN --format yaml --scope strict --cert "$cert" \
        >"$sealed"
    ;;
  *)
    printf 'ERROR: unsupported SECRET_KIND %s\n' "$SECRET_KIND" >&2
    exit 2
    ;;
esac

$KUBESEAL_BIN \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --validate <"$sealed"

mkdir -p "$(dirname "$OUTPUT")"
mv "$sealed" "$OUTPUT"
sealed=

printf 'Created strict SealedSecret %s for context %s\n' "$OUTPUT" "$actual_context"
