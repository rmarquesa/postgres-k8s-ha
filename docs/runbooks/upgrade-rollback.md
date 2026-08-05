# Upgrade and rollback runbook

## Change classes

Treat these independently:

1. CloudNativePG operator/chart upgrade;
2. PostgreSQL minor/container-image update;
3. PostgreSQL major-version upgrade;
4. Kubernetes or storage-provider upgrade.

Never combine them in one maintenance change.

## Preconditions

- release notes and compatibility matrix reviewed;
- manifests render and server dry-run successfully;
- backup/WAL archive healthy and a recent restore drill passed;
- capacity supports rolling replacement;
- alerts and application SLOs are green;
- staging uses representative data/workload;
- rollback decision time and owner are defined.

## Operator upgrade

1. Upgrade one supported version step at a time.
2. Diff CRDs, RBAC, webhook and Deployment.
3. Apply without `--force-conflicts` in production.
4. Confirm operator leader, webhook, reconciliation and all Cluster resources.
5. Do not roll PostgreSQL instances merely because the operator changed.

Rollback is allowed only when the previous operator supports the currently stored CRD/API objects. CRD downgrades are not automatically safe.

## PostgreSQL minor/image update

The production profile uses `primaryUpdateStrategy: supervised`.

1. Validate image provenance, extensions and `pg_upgrade --check` relevance.
2. Update replicas first and verify replication/queries.
3. Perform a controlled switchover in the approved window.
4. Update the former primary and verify three healthy instances.
5. Run application smoke, latency and backup/WAL checks.

Rollback to the previous image is allowed only when PostgreSQL data format and extension state remain compatible. Never assume container tag rollback reverses database changes.

## PostgreSQL major version

Use a documented logical migration or supported major-upgrade procedure in a parallel cluster. Test extension compatibility and cutover/rollback with production-scale data. A physical base backup from a newer major version cannot restore into an older major version.

## Kubernetes/storage upgrade

Respect PDBs, one node/failure domain at a time, and verify synchronous replication before each disruption. Stop if the cluster cannot maintain the approved durability state.

## Evidence

Record versions/digests, rendered diff, compatibility references, backup/restore proof, timestamps, instance order, switchover duration, application checks, alerts and rollback decision.
