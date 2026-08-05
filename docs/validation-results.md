# Validation results

Date: August 5, 2026.

Environment: k3s-Proxmox with one control-plane and three workers.

## Storage

- three Longhorn Nodes Ready and Schedulable;
- 80% reserved on each 50 GiB filesystem;
- approximately 9.48 GiB effective capacity per worker;
- `1Gi` smoke-test PVC expanded online to `2Gi`;
- write, detach/reattach, read and cleanup passed.

## PostgreSQL

- CloudNativePG `1.30.0`;
- PostgreSQL `18.3-standard-trixie`;
- three Ready instances across three workers;
- `synchronous_standby_names`: `ANY 1`;
- two replicas reported as `quorum`;
- three `5Gi` PVCs Bound on `longhorn-postgres`.

## Failover

Primary `postgres-ha-1` on `k8s-worker-1` was deleted. `postgres-ha-2` on `k8s-worker-3` was promoted.

- observed RTO until the primary was Ready: **27 seconds**;
- row confirmed before failure: preserved;
- deleted instance: rebuilt and returned Ready;
- final state: 3/3 Pods Running.

This result proves Pod loss, not complete worker loss or a universal SLA.

## Backup

Backup `postgres-ha-manual`:

- target: `prefer-standby`;
- instance: `postgres-ha-2`;
- phase: `completed`;
- start: `2026-08-05T12:26:56Z`;
- end: `2026-08-05T12:27:14Z`;
- `backup.info` found in MinIO using only the dedicated Barman credentials.

## PITR

Temporary restore `postgres-ha-restore` with one instance and a `2Gi` PVC:

- measured target: `2026-08-05 12:38:15.727956+00`;
- time until the restored cluster became Ready: **134 seconds**;
- `before` marker: `1`;
- `after` marker: `0`;
- result: temporal target respected;
- temporary Cluster, ConfigMap and PVC removed after the test.

## MinIO

- standalone Deployment with `Recreate` strategy for the RWO PVC;
- private and versioned `postgres-backups` bucket;
- default `console/console123` user removed;
- dedicated Barman user with policy restricted to the bucket;
- PUT/stat/GET/comparison/DELETE smoke test passed.

## Monitoring and security validation

- strict-scope Sealed Secrets round-trip passed without plaintext in Git;
- production monitoring manifests render successfully;
- eleven Prometheus alert rules passed `promtool` validation;
- official CloudNativePG Grafana dashboard included;
- repository and public site passed Gitleaks.

## Not yet validated

- complete abrupt worker loss;
- physical disk failure;
- `fio`/`pgbench` and fsync benchmark;
- live alert routing and target logging-stack integration;
- external object storage and production disaster recovery;
- highly available control-plane;
- PostgreSQL/operator upgrade under application load;
- production migration and rollback drill.
