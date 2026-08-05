#!/usr/bin/env bash

kustomize_apply() {
  local directory=$1
  local rendered
  local rc=0
  rendered=$(mktemp)

  "$KUBECTL_BIN" kustomize "$directory" --enable-helm >"$rendered" || rc=$?
  if (( rc == 0 )); then
    "$KUBECTL_BIN" apply --server-side \
      --force-conflicts \
      --field-manager=postgres-k8s-ha \
      -f "$rendered" || rc=$?
  fi
  rm -f "$rendered"
  return "$rc"
}
