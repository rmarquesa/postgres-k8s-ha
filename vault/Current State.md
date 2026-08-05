# Current State

## Status

The functional foundation is installed and validated on k3s-Proxmox. PostgreSQL, Pod failover, backup and PITR have been exercised against the live lab cluster.

## Completed

- Kustomize-based installation without Argo CD;
- cert-manager `v1.21.1`;
- CloudNativePG `1.30.0`;
- Barman Cloud Plugin `v0.14.0`;
- Longhorn `1.12.0`, approximately 10 GiB per worker;
- `longhorn-postgres` and `longhorn-lab` StorageClasses;
- standalone MinIO with a `2Gi` PVC and `Recreate` strategy;
- dedicated Barman user and removal of unsafe defaults;
- PostgreSQL 18.3 with three instances and three `5Gi` PVCs across three workers;
- `ANY 1`, `dataDurability: required` and two quorum replica candidates;
- Pod failover in 27 seconds with the confirmed write preserved;
- completed backup and verified object;
- PITR proven through before/after marker comparison;
- successful storage and S3 smoke tests;
- separate fail-closed production overlay with external S3, DatabaseRoles and NetworkPolicies;
- Sealed Secrets `0.38.4` / chart `2.19.1`, with a strict round-trip verified without plaintext in Git;
- CNPG/operator PodMonitors, the official dashboard and eleven alerts validated by `promtool`;
- runbooks for alerts, backup/PITR, node loss, upgrades/rollback, Secrets, migration and capacity;
- an English-language, responsive project landing page validated for GitHub Pages.

## Pending

1. storage/PostgreSQL benchmarks with calibrated thresholds;
2. abrupt worker-loss testing in an isolated environment;
3. real external object storage and a production restore/PITR drill;
4. complete production migration, including roles and application login;
5. upgrade/rollback drills and integration with the target logging stack.

See [validation results](../docs/validation-results.md), [Kustomize delivery](../docs/kustomize.md) and the [implementation contract](../docs/implementation-contract.md).
